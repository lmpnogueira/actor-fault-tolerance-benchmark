package models

import upickle.default.*


enum FaultMessageType(val value: String)derives ReadWriter:
  private case CpuIntensive extends FaultMessageType("cpu_intensive")
  private case RamIntensive extends FaultMessageType("ram_intensive")
  private case Error extends FaultMessageType("error")
  private case Random extends FaultMessageType("random")
  case NoneType extends FaultMessageType("none")

object FaultMessageType {
  def fromString(value: String): FaultMessageType = {
    value match {
      case "cpu_intensive" => CpuIntensive
      case "ram_intensive" => RamIntensive
      case "error" => Error
      case "random" => Random
      case "none" => NoneType
      case _ => throw new IllegalArgumentException()
    }
  }
}