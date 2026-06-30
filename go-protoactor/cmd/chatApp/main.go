package main

import (
	"benchmarking/chatapp/actor/internal/chat"
	"benchmarking/chatapp/actor/internal/client"
	"benchmarking/chatapp/actor/internal/models"
	"benchmarking/chatapp/actor/internal/orchestrator"
	"fmt"
	"log/slog"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		panic("There is not sufficient arguments")
	}

	// Read params
	testId := os.Args[1]
	role := os.Args[2]
	slog.Info("Starting ...", slog.String("testId", testId), slog.String("role", role))

	configFile := os.Getenv("BENCHMARK_CONFIG")
	if configFile == "" {
	    configFile = "./../configs/config.yml"	
	}
	params, err := models.LoadParams(configFile)
	if err != nil {
		panic(fmt.Sprintf("fail reading params: %v", err))
	}
	params.Print(testId)
	slog.Info("Params loaded!", slog.Any("params", params))

	if role == "chats" {
		chat.StartChatsOrchestrator()
	} else if role == "clients" {
		client.StartChatsOrchestrator()
	} else if role == "main" {
		orchestrator.StartMainOrchestrator(params, testId)
	} else {
		panic("invalid role, the possibilities are: chats, clients or main")
	}
}
