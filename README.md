# Rhasspy-FHEM
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## Contents
[About Rhasspy](#About-Rhasspy)\
[About FHEM-Rhasspy](#About-FHEM-Rhasspy)\
[Installation of Rhasspy-FHEM](#Installation-of-Rhasspy-FHEM)\
[Definition (DEF) in FHEM](#definition-def-in-fhem)\
&nbsp;&nbsp;[Set-Commands (SET)](#set-commands-set)\
&nbsp;&nbsp;[Attributes (ATTR)](#attributes-attr)\
&nbsp;&nbsp;[Readings/Events](#readings--events)\
[Configure FHEM-devices for use with Rhasspy](#configure-fhem-devices-for-use-with-rhasspy)\
&nbsp;&nbsp;[Room *Rhasspy*](#room-rhasspy)\
&nbsp;&nbsp;[Attribute *rhasspyName*](#attribute-rhasspyname)\
&nbsp;&nbsp;[Attribute *rhasspyRoom*](#attribute-rhasspyroom)\
&nbsp;&nbsp;[Assign intents with *rhasspyMapping*](#assign-intents-with-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;[Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping)\
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

## Definition (DEF) in FHEM
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
  Updated/Created Slots are
  - de.fhem.Device
  - de.fhem.Room
  - de.fhem.MediaChannels
  - de.fhem.Color
  - de.fhem.NumericType
  
  
  **Do not forget to train Rhasspy after updating slots!**

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

### Readings / Events
* **lastIntentPayload**\
  Content of the last command which was received by FHEM
* **listening_*roomname***\
  Changes to 1 if a wakeword was recognized and back to 0 if the Rhasspy-session has ended.\
  There is one reading for every single satellite/master.\
  Can for example be used to mute speakers while Rhasspy is listening to commands.
* **voiceResponse** and **textResponse**\
  Response to the last voice- or text-command.

## Configure FHEM-devices for use with Rhasspy
To control a device with voice-commands, Rhasspy needs to now about the device. This works by adding the device to the FHEM-room *Rhasspy*. When using the set-command *updateSlots*, the module Rhasspy-FHEM then creates a list of all devices in this room and saves it to a Rhasspy-slot called *de.fhem.Device*. After training Rhasspy, the device is recognized and can be controlled.


**Important**: Be sure to execute `updateSlots` and `trainRhasspy` after every change of the following attributes.


To use a FHEM-device with Rhasspy, some settings are needed:

### Room Rhasspy
Rhasspy-FHEM only searches for devices in room **Rhasspy**. Be sure to add this attribute to every device you want to control with Rhasspy.\
Example:
```
attr Bulb room Rhasspy
```

### Attribute *rhasspyName*
Every controllable FHEM-device has to have an attribute **rhasspyName**. The content of this attribute is the name you want to call this device (e.g. *Bulb*). It's possible to use multiple names for the same device by separating them with comma.\
Example:
```
attr <device> rhasspyName Bulb,Ceiling Light,Chandelier
```
It's also possible to have the same name for different FHEM-devices. Just make sure they have different *rhasspyRoom* attributes.

### Attribute *rhasspyRoom*
You can add an attribute `rhasspyRoom` to the device to tell Rhasspy in which physical room the device is. Otherwise it belongs to the "default room" you used when defining the Rhasspy-device.\
This is useful to speak commands without a room. If there is a device *Bulb* and it's *rhasspyRoom*-attribute is equal to the siteId of your satellite, it's enough to say "Bulb on" and the Bulp in the room the command is spoken will be turned on.

Example:
```attr <device> rhasspyRoom Livingroom```

### Assign intents with *rhasspyMapping*
There is no automatic detection of the right intent for a particual type of device. That's why it's necessary to create a mapping of intents a device supports.\
It's possible to assign multiple intents to a single device. Just add one line per mapping.

A mapping has to look like:
```
IntentName:option1=value1,option2=value2,...
```

Example:
```
SetOnOff:cmdOn=on,cmdOff=off
GetOnOff:currentVal=state,valueOff=off
```

#### Formatting Commands and Readings inside a *rhasspyMapping*
Some intents can use FHEM-commands or -readings to get or set values.\
There are three ways to write them:
* Directly use Set-Command or Reading of the current devices:\
  `cmd=on` or `currentReading=temperature`
* Redirect command or reading to another device:\
  `cmd=Otherdecice:on` or `currentReading=Otherdevice:temperature`
* Perl-Code to execute a command or assing a value:\
  This allows more complex requests.\
  The code has to be enclosed in curly brackets.\
  `{currentVal={ReadingsVal($DEVICE,"state",0)}`\
  or\
  `cmd={fhem("set $DEVICE dim $VALUE")}`\
  `$DEVICE` is the current FHEM-device. The *SetNumeric* intent can use `$VALUE` for the value which has to be set.

<!--
Gibt man bei der Option `currentVal` das Reading im Format *reading* oder *Device:reading* an,\
kann mit der Option `part` das Reading an Leerzeichen getrennt werden.\
Über `part=1` bestimmt ihr, dass nur der erst Teil des Readings übernommen werden soll.\
Dies ist z.B. nützlich um die Einheit hinter dem Wert abzuschneiden.
-->

## To-Do
- [ ] Move ip of Rhasspy-Master to DEF instead of ATTR
- [ ] Add Custom intents functionality
