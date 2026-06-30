import akka.actor.typed.{ActorSystem, Behavior}
import benchmarking.*
import com.typesafe.config.{Config, ConfigFactory}
import models.Params
import utils.YamlReader

import java.io.FileInputStream
import java.util.concurrent.Executors

object App {

  def main(args: Array[String]): Unit = {

    if (args.length < 2) {
      println("Needed params: <test_id> <role>")
      System.exit(1)
    }

    val testId = args(0)
    val role = args(1)

    val port = role match {
      case "main" => 2551
      case "servers" => 2552
      case _ => 2553
    }

    val config = ConfigFactory.parseString(
      s"""
            akka.remote.artery.canonical.port = $port
            akka.cluster.roles = ["$role"]
          """
    ).withFallback(ConfigFactory.load())

    println(s"Starting actor system for role: $role")

    val configFile =
      sys.env.getOrElse(
      "BENCHMARK_CONFIG",
      "./../configs/config.yml"
    )

    val inputStream = new FileInputStream(configFile)
    val params = YamlReader.readParams(inputStream)

    role match {
      case "main" =>
        startMainGuardian(testId, params, config)

      case "servers" =>
        startSupManager(config)

      case "clients" =>
        startClientManager(config)

      case other =>
        println(s"Unknown role: $other")
        System.exit(1)
    }
  }

  private def startMainGuardian(testId: String, params: Params, config: Config): Unit = {
    println(
      s"""
         |
         |################## TEST [Scala] ##################
         |Test id: $testId
         |Test type: ${params.test_type}
         |Test duration: ${params.test_duration_seconds} seconds
         |Number of supervisors: ${params.num_supervisor}
         |Chats per supervisor: ${params.chats_per_sup}
         |Clients per server: ${params.clients_per_server}
         |Message type: ${params.msg_type}
         |Fault pause (ms): ${params.fault_pause_ms}
         |###################################################
         |""".stripMargin)

    val guardianBehavior: Behavior[MainGuardianCommand] =
      MainGuardian(
        testId,
        params.test_type,
        params.test_duration_seconds,
        params.msg_type,
        params.fault_pause_ms,
        params.num_supervisor,
        params.chats_per_sup,
        params.clients_per_server
      )

    val system = ActorSystem(guardianBehavior, "Benchmarking", config)

    scheduleShutdown(system)
  }

  private def startSupManager(config: Config): Unit = {
    val managerBehavior: Behavior[ServersManagerCommand] =
      ServersManager()

    val system = ActorSystem(managerBehavior, "Benchmarking", config)
    scheduleShutdown(system)
  }

  private def startClientManager(config: Config): Unit = {
    val managerBehavior: Behavior[ClientsManagerCommand] =
      ClientsManagerActor()

    val system = ActorSystem(managerBehavior, "Benchmarking", config)
    scheduleShutdown(system)
  }

  private def scheduleShutdown(system: ActorSystem[_]): Unit = {
    val seconds = 400
    val scheduler = Executors.newScheduledThreadPool(1)
    scheduler.schedule(new Runnable {
      override def run(): Unit = {
        println(s"Shutting down ActorSystem after $seconds seconds...")
        system.terminate()
      }
    }, seconds, java.util.concurrent.TimeUnit.SECONDS)
  }
}