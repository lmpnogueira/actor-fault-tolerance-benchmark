package benchmarking

import akka.actor.typed.*
import akka.actor.typed.receptionist.{Receptionist, ServiceKey}
import akka.actor.typed.scaladsl.Behaviors
import messaging.Publisher.PublisherCommand
import models.{FaultMessageType, TestType}

import scala.concurrent.duration.*
import scala.util.Random

sealed trait ClientsManagerCommand

case class SpawnClient(
                        testId: String,
                        testType: TestType,
                        username: String,
                        main: ActorRef[MainGuardianCommand],
                        publisher: ActorRef[PublisherCommand],
                        discovery: ActorRef[DiscoveryCommand],
                        chatTopic: String
                      ) extends ClientsManagerCommand

case class SpawnInjector(name: String,
                         msgType: FaultMessageType,
                         testType: TestType,
                         waitMs: Int,
                         chatTopic: String,
                         main: ActorRef[MainGuardianCommand],
                         chat: ActorRef[ChatCommand],
                         discovery: ActorRef[DiscoveryCommand],
                         publisher: ActorRef[PublisherCommand]
                        ) extends ClientsManagerCommand

object ClientsManagerActor {

  val serviceKey: ServiceKey[ClientsManagerCommand] =
    ServiceKey[ClientsManagerCommand]("ClientsManager")

  def apply(): Behavior[ClientsManagerCommand] =
    Behaviors.setup { context =>
      context.system.receptionist ! Receptionist.Register(serviceKey, context.self)
      context.log.info("ClientsManagerActor registered with Receptionist")
      // start with counter = 0
      clientsManager(spawnClientCount = 0)
    }

  /**
   * @param spawnClientCount number of SpawnClient messages received so far
   */
  private def clientsManager(spawnClientCount: Int): Behavior[ClientsManagerCommand] =
    Behaviors.receive { (context, message) =>
      message match {
        case SpawnClient(testId, testType, username, main, publisher, discovery, chatTopic) =>
          val delay: FiniteDuration = Random.between(0, 250).millis
          context.spawn(
            Client(testId, testType, username, main, publisher, discovery, chatTopic),
            username,
            DispatcherSelector.fromConfig("spawn-dispatcher")
          )

          val newCount = spawnClientCount + 1

          context.log.info(s"[ClientsManager] Clients spawned: $spawnClientCount")
          clientsManager(newCount)

        case SpawnInjector(name, msgType, testType, waitMs, chatTopic, main, chat, discovery, publisher) =>
          context.log.info(s"Spawning Injector: $name")
          context.spawn(
            Injector(msgType, testType, waitMs, chatTopic, main, chat, discovery, publisher),
            name
          )
          Behaviors.same
      }
    }
}