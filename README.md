# Rhasspy-FHEM
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## Contents
[About Rhasspy](#About-Rhasspy)\
[About FHEM-Rhasspy](#About-FHEM-Rhasspy)\
[Installation of Rhasspy-FHEM](#Installation-of-Rhasspy-FHEM)\
&nbsp;&nbsp;[Definition (DEF)](#Definition-(DEF))\
&nbsp;&nbsp;[Set-Commands (SET)](#Set-Commands-(SET))\
&nbsp;&nbsp;[Attributes (ATTR)](#Attributes-(ATTR))\
[To-Do](#To-Do)

## About Rhasspy
Rhasspy (pronounced RAH-SPEE) is an open source, fully offline set of voice assistant services for many human languages.

## About FHEM-Rhasspy
Rhasspy consist of multiple modules (Hot-Word Detection, Text to Speech, Speech to Text, Intent Recognition, ...). All of these communicate over MQTT.

Rhasspy-FHEM evaluates these JSON-messages and converts them to commands. And it sends messages to Rhasspy to e.g. provide responses on commands to TextToSpeech.

Rhasspy-FHEM uses the 00_MQTT.pm module to receive and send these messages. Therefore it is necessary to define an MQTT device in FHEM before using Rhasspy-FHEM.

## Installation of Rhasspy-FHEM
- Download a RAW-Copy of 10_RHASSPY.pm and copy it to `opt/fhem/FHEM`
- Don't forget to change the ownership of the file to `fhem.dialout` (or whatever user/group FHEM is using).
- Restart FHEM
- Define a MQTT device which connects to the MQTT-server Rhasspy is using. E.g.:
```
define RhasspyMQTT MQTT <ip-or-hostname-of-mqtt-server>:12183 
```

### Definition (DEF)
You can define a new instance of this module with:

```
define <name> RHASSPY <MqttDevice> <DefaultRoom>
```

* `MqttDevice`: Name of the MQTT Device in FHEM which connects to the MQTT server Rhasspy uses.
* `DefaultRoom`: Name of the default room which should be used if no room-name is present in the command.

### Set-Commands (SET)
* **speak**\
  Voice output over TTS.\
  Both arguments (siteId and text) are required!\
  Example: `set <rhasspyDevice> speak siteId="default" text="This is a test"`
* **textCommand**\
  Send a text command to Rhasspy.\
  Example: `set <rhasspyDevice> textCommand turn the light on`
* **trainRhasspy**\
  Sends a train-command to the HTTP-API of the Rhasspy master.
  The attribute `rhasspyMaster` has to be defined to work.\
  Example: `set <rhasspyDevice> trainRhasspy`
* **updateSlots**\
  Sends a command to the HTTP-API of the Rhasspy master to update all slots on Rhasspy with actual FHEM-devices, rooms, etc.\
  The attribute *rhasspyMaster* has to be defined to work.\
  Example: `set <rhasspyDevice> updateSlots`\
  Do not forget to train Rhasspy afterwards!

### Attributes (ATTR)
* **rhasspyMaster**\
  Defines the URL to the Rhasspy Master for sending requests to the HTTP-API.\
  Has to be in Format `protocol://fqdn:port`.\
  Example:
  `http://rhasspy.example.com:12101`
* **response**\
  Optionally define alternative default answers.\
  Available keywords are `DefaultError`, `NoActiveMediaDevice` and `DefaultConfirmation`.\
  Example:
  ```
  DefaultError=
  DefaultConfirmation=Master, it is a pleasure doing as you wish
  ```
* **rhasspyIntents**\
  Not implemented yet
* **shortcuts**\
  Define custom sentences without editing Rhasspy sentences.ini.\
  The shortcuts are uploaded to Rhasspy when using the `updateSlots` set-command.\
  Example:
  ```
  mute on={fhem ("set receiver mute on")}
  mute off={fhem ("set receiver mute off")}
  ```
## To-Do
- [ ] Move ip of Rhasspy-Master to DEF instead of ATTR
