package utils

import models.{FaultMessageType, Params, TestType}
import org.yaml.snakeyaml.Yaml

import java.io.InputStream
import scala.jdk.CollectionConverters.*

object YamlReader {
  def readParams(yamlFile: InputStream): Params = {
    val yaml = new Yaml()
    val data = yaml.load(yamlFile).asInstanceOf[java.util.Map[String, Any]].asScala

    val params = data("params").asInstanceOf[java.util.Map[String, Any]].asScala

    Params(
      test_type = TestType.fromString(params("test_type").toString),
      test_duration_seconds = params("test_duration_seconds").toString.toInt,
      num_supervisor = params("num_supervisor").toString.toInt,
      chats_per_sup = params("chats_per_sup").toString.toInt,
      clients_per_server = params("clients_per_server").toString.toInt,
      msg_type = FaultMessageType.fromString(params("msg_type").toString),
      fault_pause_ms = params("fault_pause_ms").toString.toInt
      // NOTE: client_base_rate / client_ceil_rate are present in the YAML but are
      // intentionally not consumed here. All runtimes currently use a fixed client
      // send interval (200 ms, see Client.MSG_DELAY), so the comparison stays fair.
      // Remove these keys from the configs or implement a variable rate consistently
      // across Elixir/Scala/Go if a configurable rate is required.
    )
  }
}