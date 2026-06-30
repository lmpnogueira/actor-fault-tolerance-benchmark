package benchmarking

import akka.actor.typed.*
import akka.actor.typed.receptionist.{Receptionist, ServiceKey}
import akka.actor.typed.scaladsl.Behaviors
import benchmarking.MainGuardian.*
import messaging.Publisher.PublisherCommand

sealed trait ServersManagerCommand
case class SpawnSupervisorChat(name: String,
                               params: MainGuardianParams,
                               publisher: ActorRef[PublisherCommand],
                               discovery: ActorRef[DiscoveryCommand],
                               replyTo: ActorRef[MainGuardianCommand]) extends ServersManagerCommand


object ServersManager {

  val serviceKey: ServiceKey[ServersManagerCommand] = ServiceKey[ServersManagerCommand]("SupManager")

  def apply(): Behavior[ServersManagerCommand] =
    Behaviors.setup { context =>
      context.system.receptionist ! Receptionist.Register(serviceKey, context.self)
      serversManager()
    }

  private def serversManager(): Behavior[ServersManagerCommand] =
    Behaviors.receive { (context, message) =>
      message match {
        case SpawnSupervisorChat(name, params, publisher, discovery, replyTo) =>
          context.log.info(s"Spawning SupChat: $name")
          val sup = context.spawn(
            SupervisorChat(params.testId, name, params.numChatPerSup, publisher, discovery, replyTo),
            name
          )
          Behaviors.same
      }
    }
}