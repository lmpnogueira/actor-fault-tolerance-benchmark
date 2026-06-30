package benchmarking

import akka.actor.typed.*
import akka.actor.typed.receptionist.{Receptionist, ServiceKey}
import akka.actor.typed.scaladsl.*
import benchmarking.Chat.*
import benchmarking.Discovery.DiscoveryResponse
import messaging.Publisher.PublisherCommand

import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import scala.concurrent.duration.DurationLong

sealed trait DiscoveryCommand
final case class RegisterChat(name: String, refServer: ActorRef[ChatCommand]) extends DiscoveryCommand
final case class GetChatRef(name: String, replyTo: ActorRef[DiscoveryResponse]) extends DiscoveryCommand
final case class EndDiscoveryTestInfo(end: LocalDateTime) extends DiscoveryCommand
final case class StopDiscovery() extends DiscoveryCommand

object Discovery {

  sealed trait DiscoveryResponse
  final case class ChatNotFound(topic: String) extends DiscoveryResponse
  final case class ChatRefResponse(ref: ActorRef[ChatCommand]) extends DiscoveryResponse

  val serviceKey: ServiceKey[DiscoveryCommand] = ServiceKey[DiscoveryCommand]("DiscoveryServer")

  def apply(): Behavior[DiscoveryCommand] =
    Behaviors.setup { context =>
      context.system.receptionist ! Receptionist.Register(serviceKey, context.self)
      discovery(null, Map.empty)
    }

  private def discovery(publisher: ActorRef[PublisherCommand],
                        chats: Map[String, ActorRef[ChatCommand]]): Behavior[DiscoveryCommand] =
    Behaviors
      .receive[DiscoveryCommand] { (context, message) =>
        message match {
          case RegisterChat(name, ref) =>
            if (chats.contains(name)) {
              ref ! RegistrationFailedChat("Already registered.")
              Behaviors.same
            } else {
              context.log.info(s"[Discovery] Chat registered.")
              ref ! ChatRegistered()
              context.watch(ref)
              val newMap = chats + (name -> ref)
              discovery(publisher, newMap)
            }

          case GetChatRef(name, replyTo) =>
            //            context.log.info(s"[Discovery] Being asked about chat $name.")
            chats.get(name) match
              case Some(ref) => replyTo ! ChatRefResponse(ref)
              case None => replyTo ! ChatNotFound(name)
            Behaviors.same

          case benchmarking.EndDiscoveryTestInfo(end) =>
            val leftMsStop = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), end))
            context.scheduleOnce(leftMsStop.milliseconds, context.self, StopDiscovery())
            Behaviors.same

          case benchmarking.StopDiscovery() =>
            Behaviors.stopped
        }
      }
      .receiveSignal {
        case (context, Terminated(ref)) =>
          discovery(publisher, chats - ref.path.name)
      }
}