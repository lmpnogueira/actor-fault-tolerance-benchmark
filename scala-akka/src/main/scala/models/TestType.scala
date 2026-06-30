package models

import upickle.default.*


enum TestType(val value: String)derives ReadWriter:
  case Throughput extends TestType("throughput")
  case ReconnectionTime extends TestType("reconnection_time")
  case DetectionTime extends TestType("detection_time")

object TestType {
  def fromString(value: String): TestType = {
    value match {
      case "throughput" => Throughput
      case "reconnection_time" => ReconnectionTime
      case "detection_time" => DetectionTime
      case _ => throw new IllegalArgumentException()
    }
  }
}