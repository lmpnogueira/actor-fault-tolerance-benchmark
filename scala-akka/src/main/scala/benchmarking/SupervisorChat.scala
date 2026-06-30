package benchmarking

import akka.actor.typed.*
import akka.actor.typed.scaladsl.*
import benchmarking.MainGuardian.*
import messaging.Publisher
import messaging.Publisher.PublisherCommand

import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import scala.concurrent.duration.DurationLong


sealed trait SupChatCommand

private final case class CreateServer() extends SupChatCommand
private final case class ServerConnected(chat: ActorRef[ChatCommand]) extends SupChatCommand
final case class EndTestTimeSup(end: LocalDateTime) extends SupChatCommand
private final case class Stop() extends SupChatCommand

object SupervisorChat {

  def apply(testId: String,
            name: String,
            num: Int,
            publisher: ActorRef[PublisherCommand],
            discovery: ActorRef[DiscoveryCommand],
            main: ActorRef[MainGuardianCommand]): Behavior[SupChatCommand] =
    Behaviors.setup { context =>
      context.self ! CreateServer()
      supervisorChat(name, num, main, discovery, publisher, Set.empty, None)
    }

  private def supervisorChat(name: String,
                             totalChats: Int,
                             main: ActorRef[MainGuardianCommand],
                             discovery: ActorRef[DiscoveryCommand],
                             publisher: ActorRef[PublisherCommand],
                             chats: Set[ActorRef[ChatCommand]],
                             end: Option[LocalDateTime]): Behavior[SupChatCommand] =
    Behaviors
      .receive[SupChatCommand] { (context, message) =>
        message match {
          case CreateServer() =>
            context.log.info(s"[${context.self.path.name}] Creating chats ...")
            val newServers = (1 to totalChats).map { i =>
              val chatName = s"${name}_chat_$i"
              createChatActor(context, chatName, discovery, publisher)
            }.toSet

            supervisorChat(name, totalChats, main, discovery, publisher, Set.empty, None)

          case EndTestTimeSup(endTime) =>
            val leftMsStop = Math.max(0, ChronoUnit.MILLIS.between(LocalDateTime.now(), endTime))
            context.scheduleOnce(leftMsStop.milliseconds, context.self, Stop())
            supervisorChat(name, totalChats, main, discovery, publisher, chats, Some(endTime))

          case ServerConnected(server) =>
            val updatedChats = chats + server
            if (totalChats == updatedChats.size) {
              main ! ServerGroup(context.self, updatedChats)
            }
            supervisorChat(name, totalChats, main, discovery, publisher, updatedChats, end)

          case Stop() =>
            chats.foreach { chat =>
              context.stop(chat)
            }
            Behaviors.stopped
        }
      }
      .receiveSignal {
        case (context, Terminated(ref)) =>
          val chatName = ref.path.name
          val newChatRef = createChatActor(context, chatName, discovery, publisher)
          val chatRef = ref.asInstanceOf[ActorRef[ChatCommand]]
          val updatedChats = chats - chatRef + newChatRef
          supervisorChat(name, totalChats, main, discovery, publisher, updatedChats, end)
      }

  private def createChatActor(context: ActorContext[SupChatCommand],
                              chatName: String,
                              discovery: ActorRef[DiscoveryCommand],
                              publisher: ActorRef[PublisherCommand]): ActorRef[ChatCommand] = {
    val behavior = Behaviors
      .supervise(Chat(chatName, context.self, discovery, publisher))
      .onFailure[RuntimeException](SupervisorStrategy.stop)

    val chatRef = context.spawn(behavior, chatName, DispatcherSelector.fromConfig("spawn-dispatcher"))
    context.watch(chatRef)
    chatRef
  }
}
