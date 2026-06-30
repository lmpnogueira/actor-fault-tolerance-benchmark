package models

import upickle.default.*

case class Event(test_id: String,
                 timestamp: Long,
                 event: String,
                 value: Int,
                 name: String)derives ReadWriter