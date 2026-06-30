package publisher

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	amqp "github.com/rabbitmq/amqp091-go"
)

// Constants
const (
	EXCHANGE        = "events_exchange"
	QUEUE           = "events_queue"
	ROUTING_KEY     = "events.test"
	USERNAME        = "guest"
	PASSWORD        = "guest"
	VIRTUAL_HOST    = "/"
	HOST            = "localhost"
	PORT            = 5672
	PUBLISH_TIMEOUT = 5 * time.Second
)

// Messages
type stopPublisher struct{}

// PublisherActor
type PublisherActor struct {
	testId      string
	amqpChannel *amqp.Channel
}

// Connection string
func connString() string {
	return "amqp://" + USERNAME + ":" + PASSWORD + "@" + HOST + ":" + strconv.Itoa(PORT) + VIRTUAL_HOST
}

// Constructor for actor props
// Setup method to init RabbitMQ connection and actor props
func NewPublisherActor(testId string) actor.Actor {
	conn, err := amqp.Dial(connString())
	if err != nil {
		log.Panicf("Error dialing rabbitmq %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		panic(fmt.Sprintf("error opening channel AMQP: %v", err))
	}

	if _, err := ch.QueueDeclare(QUEUE, true, false, false, false, nil); err != nil {
		conn.Close()
		ch.Close()
		panic(fmt.Sprintf("error declaring queue AMQP: %v", err))
	}

	if err := ch.ExchangeDeclare(EXCHANGE, "topic", true, false, false, false, nil); err != nil {
		conn.Close()
		ch.Close()
		panic(fmt.Sprintf("error declaring exchange AMQP: %v", err))
	}

	if err := ch.QueueBind(QUEUE, ROUTING_KEY, EXCHANGE, false, nil); err != nil {
		conn.Close()
		ch.Close()
		panic(fmt.Sprintf("error binding queue AMQP: %v", err))
	}

	return &PublisherActor{
		testId:      testId,
		amqpChannel: ch,
	}
}

// Actor Receive implementation
func (p *PublisherActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {
	case *actor.Started:
		log.Printf("[Publisher] Starting ...")

	case *messages.PublishEvent:
		msg.Event.TestId = p.testId

		jsonMsg, err := json.Marshal(msg.Event)

		if err != nil {
			log.Printf("Failed to serialize event: %v", err)
			return
		}
		pubCtx, cancel := context.WithTimeout(context.Background(), PUBLISH_TIMEOUT)
		defer cancel()

		err = p.amqpChannel.PublishWithContext(pubCtx,
			EXCHANGE,
			ROUTING_KEY,
			false,
			false,
			amqp.Publishing{
				ContentType: "text/plain",
				Body:        jsonMsg,
			},
		)
		if err != nil {
			log.Printf("Failed to publish message: %v", err)
		}
	case *stopPublisher:
		log.Println("Stopping publisher actor")
		p.amqpChannel.Close()
		ctx.Stop(ctx.Self())
	}
}
