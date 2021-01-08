# Rhasspy-FHEM
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## Contents
[About Rhasspy](#About-Rhasspy)\
[About FHEM-Rhasspy](#About-FHEM-Rhasspy)\
[Installation of Rhasspy-FHEM](#Installation-of-Rhasspy-FHEM)\
[To-Do](#To-Do)

## About Rhasspy
Rhasspy (pronounced RAH-SPEE) is an open source, fully offline set of voice assistant services for many human languages.

## About FHEM-Rhasspy
Rhasspy consist of multiple modules (Hot-Word Detection, Text to Speech, Speech to Text, Intent Recognition, ...). All of these communicate over MQTT.

Rhasspy-FHEM evaluates these JSON-messages and converts them to commands. And it sends messages to Rhasspy to e.g. provide responses on commands to TextToSpeech.

Rhasspy-FHEM uses the 00_MQTT.pm module to receive and send these messages. Therefore it is necessary to define an MQTT device in FHEM before using Rhasspy-FHEM.

## Installation of Rhasspy-FHEM
10_SNIPS.pm nach `opt/fhem/FHEM`kopieren.
Danach FHEM neu starten.

Die Syntax zur Definition des Moduls sieht so aus:
```
define <name> SNIPS <MqttDevice> <DefaultRoom>
```

* *MqttDevice* Name des MQTT Devices in FHEM das zum MQTT Server von Snips verbindet.

* *DefaultRoom* weist die Snips Hauptinstanz einem Raum zu.\
Im Gegensatz zu weiteren Snips Satellites in anderen Räumen,\
kann die Hauptinstanz nicht umbenannt werden und heißt immer *default*.\
Um den Raumnamen bei einigen Befehlen weglassen zu können, sofern sie den aktuellen Raum betreffen ,\
muss Snips eben wissen in welchem Raum man sich befindet.\
Dies ermöglicht dann z.B. ein "Deckenlampe einschalten"\
auch wenn man mehrere Geräte mit dem Alias Deckenlampe in unterschiedlichen Räumen hat.

Beispiel für die Definition des MQTT Servers und Snips in FHEM:
```
define SnipsMQTT MQTT <ip-or-hostname-of-snips-machine>:1883
define Snips SNIPS SnipsMQTT Wohnzimmer
```

## To-Do
- [ ] Move ip of Rhasspy-Master to DEF instead of ATTR