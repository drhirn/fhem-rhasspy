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
&nbsp;&nbsp;&nbsp;&nbsp;[MediaControls](#mediacontrols)\
&nbsp;&nbsp;&nbsp;&nbsp;[MediaChannels](#mediachannels)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetColor](#setcolor)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetTime](#gettime)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetWeekDay](#getweekday)\
[Tips & Tricks](#tips--tricks)\
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
* **response** Text for the response Rhassyp will give.\
To use values from FHEM use format [Device:Reading].\
A comma within the response has to be escaped (\\, instead of ,).\
Or you can use Perl-code enclosed in curley brackets to define the response.\
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

### MediaControls

Intent to control media devices

Example-Mapping:
```
MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop
```

Options:
* **cmdPlay** Play command of the device. See chapter [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).
* **cmdPause** Command to pause the device.
* **cmdStop** Command to stop the device.
* **cmdFwd** Command to skip to the next track/channel/etc.
* **cmdBack** Command to skip to the previous track/channel/etc.

Note on issuing a voice-command without a room-name:\
As described in the *SetNumeric*-Intent, it is recommended to define a *GetOnOff*-Mapping to use the *MediaControls*-Intent without a room name.

Example-Sentences:
```
skip to next track on the radio
pause
skip video on the dvd player
stop playback
next
previous
```

### MediaChannels

Intent to change radio-/tv channels, favorites, playlists, lightscenes, ...

Instead of using the attribute *rhasspyMapping*, this intent is configured with an own attribute **rhasspyChannels** in the respective device. Reason is the multiple-line-configuration.

To add this new attribute, it's necessary to create/edit the attribute *userattr* and add:
```
attr <deviceName> userattr rhasspyChannels:textField-long
```

Afterwards write down the desired channels in the format `channelname=command`.

Values:
* **Channelname** The name you want to use in the voice-command.
* **cmd** The FHEM-command to switch to the channel.

Example-Mappings:
```
SWR3=favorite s_w_r_3
SWR1=favorite s_w_r_1
ARD=set tv channel 204
Netflix=set tv launchApp Netflix
Leselicht=set lightSceneWz scene Leselicht
```

Notice on using the commands without a device name:\
To start playback on a device without specifying the device name in the voice command, the module needs to know, which device should be used. Therefor it searches the attribute *rhasspyChannels* for suitable one. Devices in the actual or spoken room are preferred.

Example-Sentences:
```
play CNN on the radio in my office
switch to HBO
change channel on radio to BBC news
```

Example-Rhasspy-Sentences:
```
[de.fhem:MediaChannels]
\[(play|switch to|change to)] ($de.fhem.MediaChannels){Channel} [($de.fhem.Device){Device}] [($de.fhem.Room){Room}]
```

### SetColor

Intent to change light colors

Because of the multi-line settings, instead of configuring this intent with the attribute *rhasspyMapping*, a separate attribute *rhasspyColors* is used.

To add this new attribute to the device, create/edit the attribute *userattr*:\
`attr <deviceName> userattr rhasspyColors:textField-long`

Afterwards it's possible to add entries the *rhasspyColors* using following format:\
`Colorname=cmd`

Settings:
* **Colorname** The name of the color you want to use in a voice-command
* **cmd** The FHEM-command

Example-Mappings:
```
red=rgb FF0000
green=rgb 00FF00
blue=rgb 0000FF
white=ct 3000
warm white=ct 2700
```

Example-Sentences:
```
change light to green
lightstrip blue
color the light in the sleeping room white
```

Example-Rhasspy-Sentences:
```
[de.fhem:SetColor]
\[change|color] $de.fhem.Device{Device} [$de.fhem.Room{Room}] $de.fhem.Color{Color}
```

### GetTime

Intent to let Rhasspy speak the actual time.

German only. No FHEM-settings needed.

Example-Sentences:
```
wie spät ist es
sag mir die uhrzeit
```

Example-Rhasspy-Sentences:
```
[de.fhem:GetTime]
wie spät ist es
sag mir die uhrzeit
```

### GetWeekDay

Intent to let Rhasspy speak the actual day

German only. No FHEM-settings needed.

Example-Sentences:
```
welcher wochentag ist heute
weißt du welcher tag heute ist
kannst du mir bitte den wochentag sagen
```

Example-Rhasspy-Sentences:
```
[de.fhem:GetWeekday]
\[bitte] weißt du [bitte] welcher Tag heute ist [bitte]
\[bitte] kannst du mir [bitte] sagen welcher Tag heute ist [bitte]
\[bitte] könntest du mir [bitte] sagen welcher Tag heute ist [bitte]
\[bitte] kannst du mir [bitte] den [heutigen] Tag sagen [bitte]
welcher [wochentag|tag] ist heute [bitte]
welchen [wochentag|tag] haben wir heute [bitte]
```
## Tips & Tricks

### Rhasspy speaks actual state of device after switching it

JensS wrote a short script to let Rhasspy speak the actual state of a FHEM-device after switching it with a voice-command.\
Add the following to your 99_myUtils.pm

```
sub ResponseOnOff($){
  my ($dev) = @_;
  my $room;
  my $state = lc(ReadingsVal($dev,"state","in unknown state"));
  my $name = (split(/,/,AttrVal($dev,"rhasspyName","error")))[0];
  if (AttrVal($dev,"rhasspyRoom","")){$room = " in ".(split(/,/,AttrVal($dev,"rhasspyRoom","")))[0]};
  $state=~s/.*on/turned on/;
  $state=~s/.*off/turned off/;
  return "Ok - ".$name.$room." is now ".$state
}
```

and add a *response* to the *SetOnOff*-Mapping of a device

```
SetOnOff:cmdOn=on,cmdOff=off,response={ResponseOnOff($DEVICE)}
```


## To-Do
- [ ] Move IP of Rhasspy-Master to DEF instead of ATTR
- [ ] Add Custom intents functionality
- [ ] Set-/GetNumeric-Intents multilingual
- [ ] Check MediaControls-Intent. Doesn't look functional. And is german-only too.
