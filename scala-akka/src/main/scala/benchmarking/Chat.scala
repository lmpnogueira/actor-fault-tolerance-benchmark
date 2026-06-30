package benchmarking

import akka.actor.typed.*
import akka.actor.typed.receptionist.Receptionist
import akka.actor.typed.scaladsl.*
import benchmarking.Injector.*
import messaging.Publisher.PublisherCommand

import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import scala.concurrent.duration.DurationLong


sealed trait ChatCommand

final case class ConnectClient(name: String, client: ActorRef[ClientCommand]) extends ChatCommand
final case class OrganicMessage(msg: String) extends ChatCommand
final case class CrashMessage() extends ChatCommand
final case class ProcessOrganicMessage(msg: String) extends ChatCommand
final case class ChangeDiscoveryChat(agg: Option[ActorRef[DiscoveryCommand]]) extends ChatCommand
final case class RegistrationFailedChat(reason: String) extends ChatCommand
final case class ChatRegistered() extends ChatCommand
final case class ConnectInjector(injector: ActorRef[InjectorCommand]) extends ChatCommand
final case class EndTestTimeChat(end: LocalDateTime) extends ChatCommand
final case class StopChat() extends ChatCommand

object Chat {

  def apply(name: String,
            sup: ActorRef[SupChatCommand],
            discovery: ActorRef[DiscoveryCommand],
            publisher: ActorRef[PublisherCommand]): Behavior[ChatCommand] =
    Behaviors.setup { context =>
      val receptionistSubscriber =
        context.messageAdapter[Receptionist.Listing] {
          case Discovery.serviceKey.Listing(set) => ChangeDiscoveryChat(set.headOption)
        }
      context.system.receptionist ! Receptionist.Subscribe(Discovery.serviceKey, receptionistSubscriber)

      chat(name, publisher, Set.empty, sup, None, None, started = false)
    }

  private def chat(name: String,
                   publisher: ActorRef[PublisherCommand],
                   clients: Set[ActorRef[ClientCommand]],
                   supervisor: ActorRef[SupChatCommand],
                   injectorOpt: Option[ActorRef[InjectorCommand]],
                   discoveryOpt: Option[ActorRef[DiscoveryCommand]],
                   started: Boolean): Behavior[ChatCommand] =
    Behaviors.receive { (context, message) =>
      message match {
        case ConnectClient(n, client) =>
          if (clients.contains(client)) {
            client ! RegistrationFailedClient("Already registered")
            Behaviors.same
          } else {
            context.log.info(s"[${context.self.path.name}] Client $n registered. Total connected: ${clients.size}")
            client ! ClientRegistered(context.self, supervisor)
            chat(name, publisher, clients + client, supervisor, injectorOpt, discoveryOpt, started)
          }

        case OrganicMessage(msg) =>
          context.scheduleOnce(200.millis, context.self, ProcessOrganicMessage(msg))
          Behaviors.same

        case ProcessOrganicMessage(msg) =>
          clients.foreach(_ ! ReceiveMessage(msg))
          Behaviors.same

        case CrashMessage() =>
          context.log.info(s"[${context.self.path.name}] Crashing with ${clients.size}.")
          throw new RuntimeException("Simulated crash")

        case ChangeDiscoveryChat(opt) =>
          opt.foreach { d =>
            d ! RegisterChat(name, context.self)
          }
          chat(name, publisher, clients, supervisor, injectorOpt, opt.orElse(discoveryOpt), started)

        case ChatRegistered() =>
          if (!started) supervisor ! ServerConnected(context.self)
          chat(name, publisher, clients, supervisor, injectorOpt, discoveryOpt, started = true)

        case RegistrationFailedChat(_) =>
          discoveryOpt.foreach(_ ! RegisterChat(name, context.self))
          Behaviors.same

        case ConnectInjector(inj) =>
          context.log.info(s"[${context.self.path.name}] Injector connected!")
          inj ! InjectorConnectedServer()
          chat(name, publisher, clients, supervisor, Some(inj), discoveryOpt, started)

        case EndTestTimeChat(end) =>
          val leftMsStop = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), end))
          context.scheduleOnce(leftMsStop.milliseconds, context.self, StopChat())
          Behaviors.same

        case StopChat() =>
          Behaviors.stopped
      }
    }
}