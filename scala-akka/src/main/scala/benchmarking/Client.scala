package benchmarking

import akka.actor.typed.*
import akka.actor.typed.scaladsl.*
import benchmarking.Discovery.DiscoveryResponse
import benchmarking.MainGuardian.*
import messaging.Publisher
import messaging.Publisher.{PublishEvent, PublisherCommand}
import models.EventType.{ClientReconnectionTime, ConnectedTime, FaultDetected, ReceivedMessage}
import models.TestType
import models.TestType.{DetectionTime, ReconnectionTime, Throughput}

import java.time.temporal.ChronoUnit
import java.time.{Duration, Instant, LocalDateTime}
import scala.concurrent.duration.{DurationLong, FiniteDuration}
import scala.util.Random


sealed trait ClientCommand

private final case class SendMessage() extends ClientCommand
private final case class AskChatRefClient() extends ClientCommand
final case class ReceiveMessage(from: String) extends ClientCommand
final case class ChatNotFoundClient(topic: String) extends ClientCommand
final case class ChatRefResponseClient(ref: ActorRef[ChatCommand]) extends ClientCommand
final case class ChangeDiscoveryClient(agg: Option[ActorRef[DiscoveryCommand]]) extends ClientCommand
final case class ClientRegistered(server: ActorRef[ChatCommand],
                                  sup: ActorRef[SupChatCommand]) extends ClientCommand
final case class RegistrationFailedClient(reason: String) extends ClientCommand
final case class TriggerClientTest(init: LocalDateTime, end: LocalDateTime) extends ClientCommand
private final case class StopClient() extends ClientCommand

object Client {
  private final val MSG_DELAY: FiniteDuration = 200.milliseconds

  private case class ClientState(
                                  testId: String,
                                  testType: TestType,
                                  username: String,
                                  chatTopic: String,
                                  started: Boolean,
                                  disconnectedAt: Option[Instant],
                                  connectedAt: Option[Instant],
                                  discovery: ActorRef[DiscoveryCommand],
                                  discoveryAdapter: ActorRef[DiscoveryResponse],
                                  detection_count: Int
                                )

  def apply(testId: String,
            testType: TestType,
            username: String,
            main: ActorRef[MainGuardianCommand],
            publisher: ActorRef[PublisherCommand],
            discovery: ActorRef[DiscoveryCommand],
            chatTopic: String): Behavior[ClientCommand] =
    Behaviors.setup { context =>
      val discoveryAdpt: ActorRef[DiscoveryResponse] = context.messageAdapter {
        case Discovery.ChatRefResponse(ref) => ChatRefResponseClient(ref)
        case Discovery.ChatNotFound(topic) => ChatNotFoundClient(topic)
      }

      val state = ClientState(
        testId,
        testType,
        username,
        chatTopic,
        started = false,
        disconnectedAt = None,
        connectedAt = None,
        discovery,
        discoveryAdpt,
        detection_count = 0
      )
      context.log.info(s"[$username] Initiated.")
      client(state, main, publisher, Some(discovery), None)
    }

  private def client(params: ClientState,
                     main: ActorRef[MainGuardianCommand],
                     publisher: ActorRef[PublisherCommand],
                     discoveryOpt: Option[ActorRef[DiscoveryCommand]],
                     chatOpt: Option[ActorRef[ChatCommand]]): Behavior[ClientCommand] = {
    Behaviors
      .receive[ClientCommand] { (context, message) =>
        message match {
          case SendMessage() =>
            if (params.testType == Throughput) {
              chatOpt.foreach(chat => chat ! OrganicMessage("ping"))
              context.scheduleOnce(MSG_DELAY, context.self, SendMessage())
            }
            Behaviors.same

          case ReceiveMessage(from) =>
            if (params.testType == Throughput) {
              publisher ! PublishEvent(Instant.now().toEpochMilli, ReceivedMessage.value, 0, params.username)
            }
            Behaviors.same

          case AskChatRefClient() =>
            (discoveryOpt, chatOpt) match {
              case (Some(discovery), None) =>
                discovery ! GetChatRef(params.chatTopic, params.discoveryAdapter)
              case _ =>
                Behaviors.same
            }
            Behaviors.same

          case ChatRefResponseClient(chat) =>
            if (chatOpt.isEmpty) {
              chat ! ConnectClient(params.username, context.self)
              context.scheduleOnce(Random.between(0, 500).toLong.millis, context.self, AskChatRefClient())
            }
            Behaviors.same

          case ChatNotFoundClient(topic) =>
            context.scheduleOnce(Random.between(0, 500).toLong.millis, context.self, AskChatRefClient())
            Behaviors.same

          case ClientRegistered(chatRef, sup) =>
            context.watch(chatRef)
            if (!params.started) {
              main ! ClientConnected(context.self, chatRef, sup)
            }
            if (params.disconnectedAt.isDefined && params.testType == ReconnectionTime) {
              val diff = Duration.between(params.disconnectedAt.get, Instant.now()).toMillis.toInt
              publisher ! PublishEvent(Instant.now().toEpochMilli, ClientReconnectionTime.value, diff, params.username)
            }
            val newParams = params.copy(
              started = true,
              disconnectedAt = None,
              connectedAt = Some(Instant.now())
            )
            client(newParams, main, publisher, discoveryOpt, Some(chatRef))

          case RegistrationFailedClient(reason) =>
            if (chatOpt.isEmpty) {
              context.log.info(s"[${params.username}] Failed to connect.")
              context.scheduleOnce(0.milliseconds, context.self, AskChatRefClient())
            }
            Behaviors.same

          case TriggerClientTest(init, end) =>
            if (params.testType == Throughput) {
              val leftMsStart = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), init))
              context.scheduleOnce(leftMsStart.milliseconds, context.self, SendMessage())
            }

            val leftMsStop = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), end))
            context.scheduleOnce(leftMsStop.milliseconds, context.self, StopClient())

            val newParams = params.copy(started = true)
            client(newParams, main, publisher, discoveryOpt, chatOpt)

          case StopClient() =>
            context.log.info(s"[${context.self.path.name}] Stopping actor...")
            val increasedTime = Instant.now().plus(1, ChronoUnit.SECONDS).toEpochMilli
            params.connectedAt match {
              case Some(connected) if params.testType == ReconnectionTime =>
                val diff = Duration.between(connected, Instant.now()).toMillis.toInt
                publisher ! PublishEvent(increasedTime, ConnectedTime.value, diff, params.username)
              case _ =>
                publisher ! PublishEvent(increasedTime, ReceivedMessage.value, 0, params.username)
            }
            Behaviors.stopped

          case ChangeDiscoveryClient(newDiscoveryOpt) =>
            newDiscoveryOpt match {
              case Some(discovery) =>
                context.self ! AskChatRefClient()
                client(
                  params.copy(discoveryAdapter = params.discoveryAdapter),
                  main,
                  publisher,
                  Some(discovery),
                  chatOpt
                )
              case None =>
                Behaviors.same
            }
        }
      }
      .receiveSignal {
        case (context, Terminated(ref)) =>
          if (params.connectedAt.isDefined && params.testType == ReconnectionTime) {
            val diff = Duration.between(params.connectedAt.get, Instant.now()).toMillis.toInt
            publisher ! PublishEvent(Instant.now().toEpochMilli, ConnectedTime.value, diff, params.username)
          }

          if (params.testType == DetectionTime) {
            publisher ! PublishEvent(
              Instant.now().toEpochMilli,
              FaultDetected.value,
              params.detection_count,
              params.chatTopic
            )
          }

          val baseDelay = 100.milliseconds
          val reconnectJitterMs = Random.between(0, 200).toLong
          context.scheduleOnce(baseDelay + reconnectJitterMs.millis, context.self, AskChatRefClient())

          val newCounter = params.detection_count + 1
          val newParams = params.copy(
            disconnectedAt = Some(Instant.now()),
            connectedAt = None,
            detection_count = newCounter
          )
          client(newParams, main, publisher, discoveryOpt, None)
      }
  }
}