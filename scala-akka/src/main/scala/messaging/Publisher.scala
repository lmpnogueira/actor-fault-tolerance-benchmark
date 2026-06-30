package messaging

import akka.actor.typed.*
import akka.actor.typed.scaladsl.*
import com.rabbitmq.client.{Channel, ConnectionFactory}
import models.Event
import upickle.default.*

object Publisher {

  private val exchangeName = "events_exchange"
  private val queueName = "events_queue"
  private val bindingKey = "events.#"
  private val routingKey = "events.server"

  // RabbitMQ host is read from the environment so the benchmark is portable.
  // Defaults to localhost, matching the Elixir/Go runtimes and the statistics component.
  private val rabbitHost: String =
    sys.env.getOrElse("RABBITMQ_HOST", "localhost")

  sealed trait PublisherCommand

  final case class PublishEvent(timestamp: Long, eventType: String, value: Int = 0, name: String) extends PublisherCommand

  def apply(testId: String): Behavior[PublisherCommand] = Behaviors.setup { context =>
    val factory = ConnectionFactory()
    factory.setUsername("guest")
    factory.setPassword("guest")
    factory.setVirtualHost("/")
    factory.setHost(rabbitHost)
    factory.setPort(5672)

    val conn = factory.newConnection
    val channel = conn.createChannel

    channel.exchangeDeclare(exchangeName, "topic", true)
    channel.queueDeclare(queueName, true, false, false, null)
    channel.queueBind(queueName, exchangeName, bindingKey)

    running(testId, channel)
  }

  private def running(testId: String, channel: Channel): Behavior[PublisherCommand] =
    Behaviors
      .receive[PublisherCommand] { (context, message) =>
        message match {
          case PublishEvent(timestamp, eventType, value, name) =>
            val event = Event(testId, timestamp, eventType, value, name)
            val messageBodyBytes = write(event).getBytes
            channel.basicPublish(exchangeName, routingKey, null, messageBodyBytes)
        }
        Behaviors.same
      }
      .receiveSignal {
        case (context, PostStop) =>
          context.log.info("Shutting down publisher, closing RabbitMQ channel.")
          channel.close()
          channel.getConnection.close()
          Behaviors.same
      }
}