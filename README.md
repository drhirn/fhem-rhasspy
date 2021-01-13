# Rhasspy-FHEM
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## Contents
[About Rhasspy](#About-Rhasspy)\
[About FHEM-Rhasspy](#About-FHEM-Rhasspy)\
[Installation of Rhasspy-FHEM](#Installation-of-Rhasspy-FHEM)\
[Definition (DEF) in FHEM](#definition-def-in-fhem)\
&nbsp;&nbsp;&nbsp;&nbsp;[Set-Commands (SET)](#set-commands-set)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attributes (ATTR)](#attributes-attr)\
&nbsp;&nbsp;&nbsp;&nbsp;[Readings/Events](#readings--events)\
[Configure FHEM-devices for use with Rhasspy](#configure-fhem-devices-for-use-with-rhasspy)\
&nbsp;&nbsp;&nbsp;&nbsp;[Room *Rhasspy*](#room-rhasspy)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyName*](#attribute-rhasspyname)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyRoom*](#attribute-rhasspyroom)\
&nbsp;&nbsp;&nbsp;&nbsp;[Assign intents with *rhasspyMapping*](#assign-intents-with-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping)\
[Intents](#intents)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetOnOff](#setonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetOnOff](#getonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetNumeric](#setnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetNumeric](#getnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;[Status](#status)\
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
  Changes to 1 if a wake-word was recognized and back to 0 if the Rhasspy-session has ended.\
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
This is useful to speak commands without a room. If there is a device *Bulb* and it's *rhasspyRoom*-attribute is equal to the siteId of your satellite, it's enough to say "Bulb on" and the Bulb in the room the command is spoken will be turned on.

Example:
```attr <device> rhasspyRoom Livingroom```

### Assign intents with *rhasspyMapping*
There is no automatic detection of the right intent for a particular type of device. That's why it's necessary to create a mapping of intents a device supports.\
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
  `cmd=Otherdevice:on` or `currentReading=Otherdevice:temperature`
* Perl-Code to execute a command or assign a value:\
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

## Intents
Intents are used to tell FHEM what to do after receiving a voice-/text-command. This module has some build-in intents.

### SetOnOff
Intent to turn on/off, open/close, start/stop, ... devices.

Example-Mapping:

`SetOnOff:cmdOn=on,cmdOff=off`

Options:
  * **cmdOn** Command to turn the device on. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).
  * **cmdOff** Command to turn the device off. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).

Example-Spoken-Sentences:
  > turn on the light\
  > close the shutter in the bedroom\
  > start the coffee maker
 
 Example-Rhasspy-Sentences:
 ```
 [de.fhem:SetOnOff]
 (turn on|turn off|open|close|start|stop) $de.fhem.Device{Device} [$de.fhem.Room{Room}]
 ```
 
### GetOnOff
Intent to request the current state of a device.

Example-Mapping:

`GetOnOff:currentVal=state,valueOff=closed`

Options:\
*Hint: only valueOn OR valueOff need to be set. All other values are assigned the other state.*
  * **currentVal** Reading to read the current value from.
  * **valueOff** Value from *currentVal* which represents **off**.
  * **valueOn** Value from *currentVal* which represents **on**.

Example-Sentences:
  > is the light in the bathroom switched on?\
  > is the window in the living room opened?\
  > is the washer running?
  
Example-Rhasspy-Sentences:
```
[de.fhem:GetOnOff]
$de.fhem.Device{Device} [$de.fhem.Room{Room}] (switched on|switched off|running|stopped|opened|closed)
```

### SetNumeric

Intent to dim, change volume, set temperature, ...

Example-Mappings:
```
SetNumeric:currentVal=pct,cmd=dim,minVal=0,maxVal=99,step=25
SetNumeric:currentVal=brightness,minVal=0,maxVal=255,map=percent,cmd=brightness,step=1,type=Helligkeit
SetNumeric:currentVal=volume,cmd=volume,minVal=0,maxVal=99,step=10,type=Lautstärke
```

Options:
  * **currentVal** Reading which contains the acual value.
  * **part** Used to split *currentVal* into separate values. Separator is a blank. E.g. if *currentVal* is *23 C*, part=1 results in *23*
  * **cmd** Set-command of the device that should be called after analysing the voice-command.
  * **minVal** Lowest possible value
  * **maxVal** Highest possible value
  * **step** Step-size for changes (e.g. *turn the volume up*)
  * **map** Currently only one possible value: percent. See below.
  * **type** To differentiate between multiple possible SetNumeric-Intents for the same device. Currently supports only the german hard-coded values **Helligkeit**, **Temperatur**, **Sollwert**, **Lautstärke**, **Luftfeuchtigkeit**, **Batterie**, **Wasserstand**

Explanation for `map=percent`:\
If this option is set, all numeric control values are taken as percentage between *minVal* and *maxVal*.\
If there is a light-device with the setting *minVal=0* and *maxVal=255*, then "turn the light to 50" means the same as "turn the light to 50 percent". The light is then set to 127 instead of 50.

Specifics with `type=Lautstärke`:\
To use the commands *lauter* or *leiser* without the need to speak a device-name, the module has to now which device is currently playing. Thus it uses the *GetOnOff-Mappings* to search a turned on device with `type=Lautstärke`. First it searches in the actual *rhasspyRoom* (the *siteId* or - if missing - the default rhasspyRoom), next in all other *rhasspyRoom*s.\
That's why it's advisable to also set a *GetOnOff*-Mapping if using a *SetNumeric*-Mapping.

Example-sentences:
```
Stelle die Deckenlampe auf 30 Prozent
Mach das Radio leiser
Stelle die Heizung im Büro um 2 Grad wärmer Lauter
```

Example-Rhasspy-Sentences:
```
[de.fhem:SetNumeric]
\[stelle|mache|schalte] $de.fhem.Device{Device} [$de.fhem.Device{Room}] [auf|um] [(0..100){Value}] [(prozent|grad|dezibel){Unit}] [(heller|dunkler|leiser|lauter|wärmer|kälter){Change}]
```

### GetNumeric

Intent to question values like actual temperature, brightness, volume, ...

Example-Mappings:
```
GetNumeric:currentVal=temperature,part=1
GetNumeric:currentVal=brightness,type=Helligkeit
```

Optionen:
* **currentVal** Reading which contains the value.
* **part** Used to split *currentVal* into separate values. Separator is a blank. E.g. if *currentVal* is *23 C*, part=1 results in *23*
* **map** See Explanation in [SetNumeric Intent](#setnumeric). Converts the given value back to a percent-value.
* **minVal** Lowest possible value. Only needed if *map* is used.
* **maxVal** Highest possible value. Only needed if *map* is used.
* **type** To differentiate between multiple possible SetNumeric-Intents for the same device. Currently supports only the german hard-coded values **Helligkeit**, **Temperatur**, **Sollwert**, **Lautstärke**, **Luftfeuchtigkeit**, **Batterie**, **Wasserstand**

Example-Sentences:
```
Wie ist die Temperatur vom Thermometer im Büro?
Auf was ist das Thermostat im Bad gestellt?
Wie hell ist die Deckenlampe?
Wie laut ist das Radio im Wohnzimmer?
```

Example-Rhasspy-Sentences:
```
[de.fhem:GetNumeric]
(wie laut|wie ist die lautstärke){Type:Lautstärke} $de.fhem.Device{Device} [$de.fhem.Room{Room}]
(wie ist die|wie warm ist es){Type:Temperatur} [temperatur] [$de.fhem.Device{Device} ] [$de.fhem.Room{Room}]
\[(wie|wie ist die)] (hell|helligkeit){Type:Helligkeit} $de.fhem.Device{Device} [$de.fhem.Room{Room}]
```

### Status

Intent to get specific information of a device. The respone can be defined.

Example-Mappings:
```
Status:response="Temperature is [Thermo:temp] degree ati [Thermo:hum] percent humidity"
Status:response={my $value=ReadingsVal("device","reading",""); return "The value is $value";}
Status:response={my $value=ReadingsVal("$DEVICE","brightness",""); return "Brightness is $value";}
```

Options:
* **response** Text for the response Rhassyp will give.
To use values from FHEM use format [Device:Reading].
  A comma within the response has to be escaped (\, instead of ,).
  Or you can use Perl-code enclosed in curley brackets to define the response.
  Mixing text and Perl-code is not supported.

Example-Sentences:
```
How is the state of the thermostat in the kitchen
state light in livingroom
state washer
```

Example-Rhasspy-Sentences:
```
[de.fhem:Status]
\[how is the] (state) $de.fhem.Device{Device} [$de.fhem.Room{Room}]
```

## To-Do
- [ ] Move IP of Rhasspy-Master to DEF instead of ATTR
- [ ] Add Custom intents functionality
- [ ] Set-/GetNumeric-Intents multilingual
