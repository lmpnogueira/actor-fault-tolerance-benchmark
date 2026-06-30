package benchmarking

import akka.actor.typed.*
import akka.actor.typed.scaladsl.*
import benchmarking.Discovery.DiscoveryResponse
import benchmarking.MainGuardian.*
import messaging.Publisher.{PublishEvent, PublisherCommand}
import models.EventType.FaultInjected
import models.FaultMessageType.NoneType
import models.TestType.DetectionTime
import models.{FaultMessageType, TestType}

import java.time.temporal.ChronoUnit
import java.time.{Instant, LocalDateTime}
import scala.concurrent.duration.{DurationInt, DurationLong}


sealed trait InjectorCommand

private final case class SendFaultMessage() extends InjectorCommand
private final case class AskChatRefInjector() extends InjectorCommand
final case class InjectorConnectedServer() extends InjectorCommand
final case class ChatNotFoundInjector(topic: String) extends InjectorCommand
final case class ChatRefResponseInjector(ref: ActorRef[ChatCommand]) extends InjectorCommand
final case class TriggerInjectorTest(init: LocalDateTime, end: LocalDateTime, waitMs: Int) extends InjectorCommand
final case class StopInjector() extends InjectorCommand

object Injector {

  private case class InjectorParams(msgType: FaultMessageType,
                                    testType: TestType,
                                    waitMs: Int,
                                    chatTopic: String,
                                    discovery: ActorRef[DiscoveryCommand],
                                    discoveryAdapter: ActorRef[DiscoveryResponse],
                                    publisher: ActorRef[PublisherCommand],
                                    injectCounter: Int,
                                    chatOpt: Option[ActorRef[ChatCommand]])

  def apply(msgType: FaultMessageType,
            testType: TestType,
            waitMs: Int,
            chatTopic: String,
            main: ActorRef[MainGuardianCommand],
            chat: ActorRef[ChatCommand],
            discovery: ActorRef[DiscoveryCommand],
            publisher: ActorRef[PublisherCommand]): Behavior[InjectorCommand] =
    Behaviors.setup { context =>
      if (chat != null) chat ! ConnectInjector(context.self)
      context.watch(chat)
      context.log.info(s"[${context.self.path.name}] Init.")

      val discoveryAdpt: ActorRef[DiscoveryResponse] = context.messageAdapter {
        case Discovery.ChatRefResponse(ref) => ChatRefResponseInjector(ref)
        case Discovery.ChatNotFound(topic) => ChatNotFoundInjector(topic)
      }
      val params = InjectorParams(msgType, testType, waitMs, chatTopic, discovery, discoveryAdpt, publisher, 0, Option(chat))
      injector(params, main)
    }

  private def injector(params: InjectorParams,
                       main: ActorRef[MainGuardianCommand]): Behavior[InjectorCommand] = {
    Behaviors
      .receive[InjectorCommand] { (context, message) =>
        message match {
          case SendFaultMessage() =>
            context.log.info(s"[${context.self.path.name}] Calling SendFaultMessage")

            params.chatOpt.foreach { ch =>
              if (params.testType == DetectionTime) {
                // 0-based counter, consistent with the detection side (Client) and the
                // Elixir/Go runtimes. The (name, value) pair is what the statistics
                // component uses to match an injection with its detection.
                params.publisher ! PublishEvent(
                  Instant.now().toEpochMilli,
                  FaultInjected.value,
                  params.injectCounter,
                  params.chatTopic
                )
              }
              ch ! CrashMessage()
              context.log.info(s"[${context.self.path.name}] Fault sent to ${ch.path.name}")
            }

            if (params.msgType != NoneType) {
              context.scheduleOnce(params.waitMs.milliseconds, context.self, SendFaultMessage())
            }
            injector(params.copy(injectCounter = params.injectCounter + 1), main)

          case InjectorConnectedServer() =>
            main ! InjectorConnectedMain(context.self)
            Behaviors.same

          case AskChatRefInjector() =>
            context.log.info(s"[${context.self.path.name}] Asking discovery about chat")
            params.discovery ! GetChatRef(params.chatTopic, params.discoveryAdapter)
            Behaviors.same

          case ChatRefResponseInjector(newChat) =>
            context.log.info(s"[${context.self.path.name}] Discovery returned a valid chat: ${newChat.path.name}")
            context.watch(newChat)
            injector(params.copy(chatOpt = Some(newChat)), main)

          case ChatNotFoundInjector(topic) =>
            context.log.info(s"[${context.self.path.name}] Chat topic not found: $topic. Will retry shortly.")
            // schedule a retry to avoid busy-looping
            context.scheduleOnce(250.millis, context.self, AskChatRefInjector())
            Behaviors.same

          case TriggerInjectorTest(init, end, _waitMsFromMsg) =>
            if (params.msgType == NoneType) {
              Behaviors.stopped
            } else {
              val initPlusFaultWait = init.plus(params.waitMs, ChronoUnit.MILLIS)
              val leftMsStart = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), initPlusFaultWait))
              context.scheduleOnce(leftMsStart.milliseconds, context.self, SendFaultMessage())

              val leftMsStop = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), end))
              context.scheduleOnce(leftMsStop.milliseconds, context.self, StopInjector())
              Behaviors.same
            }

          case StopInjector() =>
            context.log.info(s"[${context.self.path.name}] Stopping.")
            Behaviors.stopped
        }
      }
      .receiveSignal {
        case (context, Terminated(ref)) =>
          context.log.info(s"[${context.self.path.name}] Observed termination of ${ref.path.name}, " +
            s"clearing chat and retrying discovery.")
          context.scheduleOnce(250.millis, context.self, AskChatRefInjector())
          injector(params.copy(chatOpt = None), main)
      }
  }
}