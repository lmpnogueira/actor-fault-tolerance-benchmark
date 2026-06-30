package benchmarking

import akka.actor.typed.*
import akka.actor.typed.receptionist.Receptionist
import akka.actor.typed.scaladsl.*
import benchmarking.*
import messaging.Publisher
import messaging.Publisher.{PublishEvent, PublisherCommand}
import models.EventType.{EndInfo, TestStarted}
import models.{FaultMessageType, TestType}

import java.time.temporal.ChronoUnit
import java.time.{Instant, LocalDateTime, ZoneId}


private val SETUP_COOLDOWN_SECONDS = 20

sealed trait MainGuardianCommand

private final case class CreateChats() extends MainGuardianCommand
final case class ServerGroup(sup: ActorRef[SupChatCommand], chats: Set[ActorRef[ChatCommand]]) extends MainGuardianCommand
private final case class CreateClients() extends MainGuardianCommand
final case class ClientConnected(client: ActorRef[ClientCommand],
                                 chat: ActorRef[ChatCommand],
                                 sup: ActorRef[SupChatCommand]) extends MainGuardianCommand
private final case class CreateFaultInjectors() extends MainGuardianCommand
final case class InjectorConnectedMain(injector: ActorRef[InjectorCommand]) extends MainGuardianCommand
private final case class InitTest() extends MainGuardianCommand
private final case class ChangeServersManager(agg: Option[ActorRef[ServersManagerCommand]]) extends MainGuardianCommand
private final case class ChangeClientsManager(agg: Option[ActorRef[ClientsManagerCommand]]) extends MainGuardianCommand

object MainGuardian {

  // State auxiliary
  case class MainGuardianParams(testId: String,
                                testType: TestType,
                                serversManager: ActorRef[ServersManagerCommand],
                                clientsManager: ActorRef[ClientsManagerCommand],
                                testDurationSeconds: Int,
                                msgType: FaultMessageType,
                                faultPauseMs: Int,
                                numSup: Int,
                                numChatPerSup: Int,
                                totalChats: Int,
                                clientsPerServer: Int,
                                totalClients: Int,
                                managers: Int = 0,
                                createdChats: Int = 0,
                                connectedClients: Int = 0,
                                connectedInjectors: Int = 0)

  private case class GroupState(chat: ActorRef[ChatCommand],
                                clients: Set[ActorRef[ClientCommand]],
                                injector: ActorRef[InjectorCommand] = null)

  def apply(testId: String,
            testType: TestType,
            testDurationSeconds: Int,
            msgType: FaultMessageType,
            waitMs: Int,
            numSup: Int,
            numChatPerSup: Int,
            clientsPerServer: Int): Behavior[MainGuardianCommand] =
    Behaviors.setup { context =>
      val discovery = context.spawn(Discovery(), "discovery")

      val receptionistSubscriber: ActorRef[Receptionist.Listing] = context.messageAdapter {
        case ServersManager.serviceKey.Listing(set) => ChangeServersManager(set.headOption)
        case ClientsManagerActor.serviceKey.Listing(set) => ChangeClientsManager(set.headOption)
      }
      context.system.receptionist ! Receptionist.Subscribe(ServersManager.serviceKey, receptionistSubscriber)
      context.system.receptionist ! Receptionist.Subscribe(ClientsManagerActor.serviceKey, receptionistSubscriber)

      val publisher = context.spawn(Publisher(testId), s"publisher_${context.self.path.name}")
      val totalChats = numChatPerSup * numSup
      val totalClients = totalChats * clientsPerServer
      val params = MainGuardianParams(testId = testId,
        testType = testType,
        clientsManager = null,
        serversManager = null,
        testDurationSeconds = testDurationSeconds,
        msgType = msgType,
        faultPauseMs = waitMs,
        numSup = numSup,
        numChatPerSup = numChatPerSup,
        totalChats = totalChats,
        clientsPerServer = clientsPerServer,
        totalClients = totalClients)
      mainGuardian(params, discovery, publisher, Map.empty)
    }

  private def mainGuardian(params: MainGuardianParams,
                           discovery: ActorRef[DiscoveryCommand],
                           publisher: ActorRef[PublisherCommand],
                           groups: Map[ActorRef[SupChatCommand], List[GroupState]]): Behavior[MainGuardianCommand] =
    Behaviors.receive[MainGuardianCommand] { (context, message) =>
      message match {

        case ChangeServersManager(supUpdate) =>
          context.log.info("Received servers manager update ... " + supUpdate)
          supUpdate match {
            case Some(sup) =>
              val newParams = params.copy(serversManager = sup, managers = params.managers + 1)
              if (newParams.managers == 2) {
                context.self ! CreateChats()
              }
              mainGuardian(newParams, discovery, publisher, groups)
            case None =>
              Behaviors.same
          }

        case ChangeClientsManager(update) =>
          context.log.info("Received clients manager update ... " + update)
          update match {
            case Some(updatedManager) =>
              val newParams = params.copy(clientsManager = updatedManager, managers = params.managers + 1)
              if (newParams.managers == 2) {
                context.self ! CreateChats()
              }
              mainGuardian(newParams, discovery, publisher, groups)
            case None =>
              Behaviors.same
          }

        // 1. Create Supervisor and subsequents the child chats
        case CreateChats() =>
          context.log.info("Creating supervisors chats ...")
          (1 to params.numSup).foreach { i =>
            val name = s"sup_$i"
            params.serversManager ! SpawnSupervisorChat(name, params, publisher, discovery, context.self)
          }
          Behaviors.same

        case ServerGroup(sup, chats) =>
          val newGroupsList = chats.foldLeft(List.empty[GroupState]) { (acc, chat) =>
            GroupState(chat, Set.empty) :: acc
          }
          val updatedGroupsState = groups + (sup -> newGroupsList)
          val updatedParams = params.copy(
            createdChats = params.createdChats + chats.size,
          )
          if (updatedParams.createdChats == params.totalChats) {
            context.log.info(s"All ${params.totalChats} chats are created. Moving on ...")
            context.log.info(s"params.createdChats: $updatedGroupsState  ...")
            context.self ! CreateClients()
          }

          mainGuardian(updatedParams, discovery, publisher, updatedGroupsState)

        // 2. Connect clients to each chat
        case CreateClients() =>
          context.log.info("Creating clients ...")
          groups.foreach { case (sup, groupStates) =>
            groupStates.zipWithIndex.foreach { case (groupState, index) =>
              (1 to params.clientsPerServer).foreach { i =>
                val name = s"client_${i}_${groupState.chat.path.name}"
                params.clientsManager ! SpawnClient(params.testId,
                  params.testType,
                  name,
                  context.self,
                  publisher,
                  discovery,
                  groupState.chat.path.name)
              }
            }
          }
          Behaviors.same

        case ClientConnected(client, chat, sup) =>
          groups.get(sup) match
            case Some(groupStates) =>
              val updatedGroupStates = groupStates.map { groupState =>
                if (groupState.chat == chat) {
                  groupState.copy(clients = groupState.clients + client)
                } else {
                  groupState
                }
              }
              val newGroups = groups + (sup -> updatedGroupStates)
              val newParams = params.copy(connectedClients = params.connectedClients + 1)
              context.log.info(s"Clients connected: ${params.connectedClients}")
              if (newParams.connectedClients == newParams.totalClients) {
                context.log.info(s"All ${params.connectedClients + 1} clients are connected of ${params.totalClients}")
                context.self ! CreateFaultInjectors()
              }
              mainGuardian(newParams, discovery, publisher, newGroups)

            case None =>
              context.log.warn(s"Supervisor not recognized: ${sup.path.name}")
              Behaviors.same

        // 3. Create the injectors
        case CreateFaultInjectors() =>
          context.log.info(s"Creating injectors ...")
          val newGroups = groups.foldLeft(Map.empty[ActorRef[SupChatCommand], List[GroupState]]) { case (acc, groupStates) =>
            val newGroupStates = groupStates._2.map { group =>
              val name = s"injector_chat_${group.chat.path.name}"
              group.copy(injector = null)

              params.clientsManager ! SpawnInjector(
                name, params.msgType,
                params.testType,
                params.faultPauseMs,
                group.chat.path.name,
                context.self,
                group.chat,
                discovery,
                publisher)

            }
            acc + (groupStates._1 -> null)
          }
          Behaviors.same

        case InjectorConnectedMain(injector) =>
          val newParams = params.copy(connectedInjectors = params.connectedInjectors + 1)
          if (newParams.connectedInjectors == newParams.totalChats) {
            context.log.info(s"All ${newParams.connectedInjectors} injectors are connected")
            context.self ! InitTest()
          }
          mainGuardian(newParams, discovery, publisher, groups)

        // 4. Trigger the tests on clients and injectors
        case InitTest() =>
          val initTime = Instant.now().plus(SETUP_COOLDOWN_SECONDS, ChronoUnit.SECONDS)
          val initTimeTimestamp = initTime.toEpochMilli
          publisher ! PublishEvent(initTimeTimestamp, TestStarted.value, 0, "main_guardian")

          val endTime = initTime.plus(params.testDurationSeconds + 1, ChronoUnit.SECONDS)
          val endTimeTimestamp = endTime.toEpochMilli
          publisher ! PublishEvent(endTimeTimestamp, EndInfo.value, 0, "main_guardian")

          context.log.info("Test initiated!")
          context.log.info(s"Test times: $initTime - $endTime")

          val initLocalDateTime = LocalDateTime.ofInstant(initTime, ZoneId.systemDefault())
          val endLocalDateTime = LocalDateTime.ofInstant(endTime, ZoneId.systemDefault())
          groups.foreach { case (sup, groupStates) =>
            sup ! EndTestTimeSup(endLocalDateTime)
            groupStates.foreach { groupState =>
              groupState.chat ! EndTestTimeChat(endLocalDateTime)
              // Mount the path
              val name = s"injector_chat_${groupState.chat.path.name}"
              val resolver = ActorRefResolver(context.system)
              val path = "akka://Benchmarking@192.168.1.70:2553/user/" + name // TODO: turn dynamically
              val injectorRef: ActorRef[TriggerInjectorTest] = resolver.resolveActorRef(path)

              injectorRef ! TriggerInjectorTest(initLocalDateTime, endLocalDateTime, params.faultPauseMs)

              groupState.clients.foreach { client =>
                client ! TriggerClientTest(initLocalDateTime, endLocalDateTime)
              }
            }
          }
          Behaviors.same
      }
    }
}