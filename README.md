# Rhasspy-Fhem
FHEM module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## About Rhasspy
Rhasspy (pronounced RAH-SPEE) is an open source, fully offline set of voice assistant services for many human languages.

## About Fhem-Rhasspy
Rhasspy consist of multiple modules (Hot-Word Detection, Text to Speech, Speech to Text, Intent Recognition, ...). All of these communicate over MQTT.

Rhasspy-Fhem evaluates these JSON-messages and converts them to commands. And it sends messages to Rhasspy to e.g. provide responses on commands to TextToSpeech.

Rhasspy-Fhem uses the 00_MQTT.pm module to receive and send these messages. Therefore it is necessary to define an MQTT device in FHEM before using Rhasspy-Fhem.