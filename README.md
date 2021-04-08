# FHEM-rhasspy
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

Thanks to Thyraz, who did all the groundwork with his [Snips-Module](https://github.com/Thyraz/Snips-Fhem).

## Contents
[Read First](#Read-First)\
[About Rhasspy](#About-Rhasspy)\
[About FHEM-rhasspy](#About-FHEM-rhasspy)\
[Installation of FHEM-rhasspy](#Installation-of-FHEM-rhasspy)\
[Definition (DEF) in FHEM](#definition-def-in-fhem)\
&nbsp;&nbsp;&nbsp;&nbsp;[Set-Commands (SET)](#set-commands-set)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attributes (ATTR)](#attributes-attr)\
&nbsp;&nbsp;&nbsp;&nbsp;[Readings/Events](#readings--events)\
[Additionals remarks on MQTT2-IOs](#additionals-remarks-on-mqtt2-ios)\
[Configure FHEM-devices for use with Rhasspy](#configure-fhem-devices-for-use-with-rhasspy)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyName*](#attribute-rhasspyname)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyRoom*](#attribute-rhasspyroom)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyMapping*](#attribute-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyChannels*](#attribute-rhasspychannels)\
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
&nbsp;&nbsp;&nbsp;&nbsp;[SetTimer](#settimer)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetMute](#setmute)\
&nbsp;&nbsp;&nbsp;&nbsp;[ReSpeak](#respeak)\
[Custom Intents](#custom-intents)\
[Tips & Tricks](#tips--tricks)\
&nbsp;&nbsp;&nbsp;&nbsp;[Rhasspy speaks actual state of device after switching it](#rhasspy-speaks-actual-state-of-device-after-switching-it)\
[To-Do](#To-Do)

## Read First
In this documentation\
**RHASSPY** refers to this FHEM-module or the FHEM-device\
**Rhasspy** refers to the Rhasspy Voice Assistant

## About Rhasspy
Rhasspy (pronounced RAH-SPEE) is an open source, fully offline set of voice assistant services for many human languages.

## About FHEM-rhasspy
Rhasspy consist of multiple modules (Hot-Word Detection, Text to Speech, Speech to Text, Intent Recognition, ...). All of these communicate over MQTT.

FHEM-rhasspy evaluates these JSON-messages and converts them to commands. And it sends messages to Rhasspy to e.g. provide responses on commands to TextToSpeech.

FHEM-rhasspy uses the 00_MQTT2_CLIENT.pm module to receive and send these messages. Therefore it is necessary to define an MQTT2_CLIENT device in FHEM before using FHEM-rhasspy.

## Installation of FHEM-rhasspy
- Download a RAW-Copy of 10_RHASSPY.pm and copy it to `opt/fhem/FHEM`
- Don't forget to change the ownership of the file to `fhem.dialout` (or whatever user/group FHEM is using).
- Restart FHEM
- Define a MQTT2_CLIENT device which connects to the MQTT-server Rhasspy is using. E.g.:
```
define RhasspyMQTT2 MQTT2_CLIENT <ip-or-hostname-of-mqtt-server>:12183 
```
- Change the `clientOrder` to set the right notification order:
```
attr <DeviceName> clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE
```
- Add MQTT-subscriptions needed for this module:
```
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded
```

## Definition (DEF) in FHEM
You can define a new instance of this module with:

```
define <name> RHASSPY <WebIF> <devspec> <defaultRoom> <language> <fhemId> <prefix> <useGenericAttrs> <encoding>
```

All parameters are optional but changing them later may result in confusing results. So it's recommended to add them when first defining the module.

* `WebIF`: The url of the Rhasspy service web-interface. If using a base and multiple satellites, use the url of the base. Default is `WebIF=http://127.0.0.1:12101`. Make sure, this is set to correct values (IP and Port)!
* `devspec`: [devspec](https://commandref.fhem.de/commandref.html#devspec) of the device(s) that should be controlled with Rhasspy. Default is `devspec=room=Rhasspy`.
* `defaultRoom`: Name of the default room which should be used if no room-name is present in the command. Default is `defaultRoom=default`.
* `language`: Language of the voice commands spoken to Rhasspy. Default is derived from global, which defaults to `language=en`.
* `fhemId`: Used to differ between multiple instances of RHASSPY on the MQTT side. Also is a part of the topic tree the corresponding RHASSPY is listening to. Default is `fhemId=fhem`.
* `prefix`: Used to differ between multiple instances of RHASSPY on the FHEM-internal side. Usefull, if you have several instances of RHASSPY in one FHEM running and want e.g. to use different identifier for groups and rooms (e.g. a different language). Default is `prefix=rhasspy`.
* `useGenericAttrs`: By default, RHASSPY only uses it's own attributes (see list below) to identifiy options for the subordinated devices you want to control. Activating this with `useGenericAttrs=1` adds `genericDeviceType` to the global attribute list and activates RHASSPYs feature to estimate appropriate settings - similar to rhasspyMapping. Default is empty.

Simple-Example:
```
define Rhasspy RHASSPY
```

Full-Example:
```
define Rhasspy RHASSPY WebIf=http://rhasspy:12101 devspec=room=Rhasspy defaultRoom=default language=en fhemId=fhem prefix=rhasspy useGenericAttrs=1
```

### Set-Commands (SET)
* **customSlot**\
  Update a single Rhasspy-slot
* **fetchSiteIds**\
  Fetch all available siteIds from Rhasspy-Base and create a reading _siteIds_. Used for e.g. to determine on which Rhasspy satellite the user gets informed that a timer has ended.\
  Has to be executed everytime a new satellite is installed or a new siteId is added to Rhasspy.
  Example: `set <rhasspyDevice> fetchSiteIds`
* **play**\
  Send a WAV file to Rhasspy.\
  Both arguments (siteId and path) are required!\
  Example: `set <rhasspyDevice> play siteId="default" path="/opt/fhem/test.wav"`
* **speak**\
  Voice output over TTS.\
  Both arguments (siteId and text) are required!\
  Example: `set <rhasspyDevice> speak siteId="default" text="This is a test"`
* **textCommand**\
  Send a text command to Rhasspy.\
  Example: `set <rhasspyDevice> textCommand turn the light on`
* **trainRhasspy**\
  Sends a train-command to the HTTP-API of the Rhasspy base.\
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
* **update**
  * **devicemap**\
    When the configuration work to RHASSPY and all subordinated devices is finished or there had been changes, issuing a devicemap-update is mandatory, to get the RHASSPY data structure updated, inform Rhasspy on changes that may have occured (update slots) and initiate a training on updated slot values etc.
	Has to be executed after changes to the attributes of a Rhasspy-controlled devices or the RHASSPY device itself.\
	Example: `set <rhasspyDevice> update devicemap`
  * **devicemap_only**\
    Used to check whether attribute changes have found their way to the data structure. This will neither update slots nor initiate any training towards Rhasspy.\
	Example: `set <rhasspyDevice> update devicemap_only`
  * **slots**\
    May be helpful after checks on the FHEM side to update all Rhasspy slots and initiate training.\
	Example: `set <rhasspyDevice> update slots`
  * **slots_no_training**\
	Same as `slots` without starting a training after updating.\
	Example: `set <rhasspyDevice> update slots_no_training`
  * **language**\
    Reinitialization of language file.\
    Be sure to execute this command after changing something in the language-configuration files or the attribut `configFile`!\
    Example: `set <rhasspyDevice> update language`
  * **all**\
    Update devicemap and language.\
	Example: `set <rhasspyDevice> update all`
* **volume**\
	Sets volume of given siteId between 0 and 1 (float)\
    Both arguments (siteId and volume) are required!\
    Example: `set <rhasspyDevice> siteId="default" volume="0.5"`
  
  
  **Do not forget to issue an `update devicemap` after making any changes to Rhasspy-controlled devices, the language file or the RHASSPY-device itself!**

### Attributes (ATTR)
* **IODev**\
  The MQTT2_CLIENT device FHEM-rhasspy is connected to.
  Example: `attr <rhasspyDevice> IODev rhasspyMQTT2`
* **configFile**\
  Path to the language-config file. If this attribute isn't set, english is used for voice responses.\
  Example: `attr <rhasspyDevice> configFile /opt/fhem/.config/rhasspy/rhasspy-de.cfg`
* **forceNEXT**\
  If set to 1, RHASSPY will forward incoming messages also to further MQTT2-IO-client modules like MQTT2_DEVICE, even if the topic matches to one of it's own subscriptions. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also [clientOrder](https://commandref.fhem.de/commandref.html#MQTT2_CLIENT) attribute in MQTT2 IO-type commandrefs. Setting this in one instance of RHASSPY might affect others, too.
* **response**\
  **Not recommended. Use the language-file instead**\
  Optionally define alternative default answers.\
  Available keywords are `DefaultError`, `NoActiveMediaDevice` and `DefaultConfirmation`.\
  Example:
  ```
  DefaultError=
  DefaultConfirmation=Master, it is a pleasure doing as you wish
  ```
* **rhasspyIntents**\
  Define custom intents for functions in 99_myUtils.pm.\
  One intent per line.\
  Example: `attr <rhasspyDevice> rhasspyIntents SetCustomIntentsTest=SetCustomIntentsTest(siteId,Device)`\
  together with the follwoing myUtils-Code should get a short impression of the possibilities:
  ```
  sub SetCustomIntentsTest {
      my $room = shift; 
      my $type = shift;
      Log3('rhasspy',3 , "RHASSPY: Room $room, Type $type");
      return "RHASSPY: Room $room, Type $type";
  }
  ```

  The following arguments can be handed over:
  * NAME => name of the RHASSPY device addressed
  * DATA => entire JSON-$data (as parsed internally)
  * siteId, Device etc. => any element out of the JSON-$data

* **shortcuts**\
  Define custom sentences without editing Rhasspy sentences.ini.\
  The shortcuts are uploaded to Rhasspy when using the `update devicemap` set-command.\
  One shortcut per line, syntax is either a simple or an extended version.\
  Examples:
  ```
  mute on=set amplifier2 mute on
  lamp off={fhem("set lampe1 off")}
  i="you are so exciting" f="set $NAME speak siteId='livingroom' text='Thanks a lot, you are even more exciting!'"
  i="mute off" p={fhem ("set $NAME mute off")} n=amplifier2 c="Please confirm!"
  ```

  Abbreviations explanation:
  * **i**: intent\
    Lines starting with `i=` will be interpreted as extended version, so if you want to use that syntax style, starting with `i=` is mandatory.
  * **f**: FHEM command\
    Syntax as usual in FHEMWEB command field.
  * **p**: perl command\
    Syntax as usual in FHEMWEB command field, enclosed in {}; this has priority to `f=`.
  * **n**: device name(s)\
    Device name(s, comma separated) that will be handed over to fhem.pl as updated devices. Needed for triggering further actions and longpoll! If not set, the return value of the called function will be used.
  * **r**: response\
    Response to be set to the caller. If not set, the return value of the called function will be used.\
	You may ask for confirmation as well using the following (optional) shorts:
    * **c**: Either numeric or text. If numeric: Timeout to wait for automatic cancellation. If text: response to send to ask for confirmation.
    * **ct**: Numeric value for timeout in seconds, default: 15

* **rhasspyTweaks**
  Not fully implemented yet.\
  Could be the place to configure additional things like additional siteId2room info or code links, allowed commands, duration of SetTimer sounds, confirmation requests etc.

### Readings / Events
* **lastIntentPayload**\
  Content of the last command which was received by FHEM
* **listening_*roomname***\
  Changes to 1 if a wake-word was recognized and back to 0 if the Rhasspy-session has ended.\
  There is one reading for every single satellite/master.\
  Can for example be used to mute speakers while Rhasspy is listening to commands.
* **responseType**\
  Shows the type of the last response.\
  Possible values are `text` or `voice`.
* **voiceResponse** and **textResponse**\
  Response to the last voice- or text-command.
* **mute_*roomname***\
  Shows if a room/siteId is muted and doesn't execute any commands.\
  There is one reading for every siteId.\
  Default is 0.
* **siteIds**\
  Reading contains every available siteId.\
  Can be updated with running `fetchSiteIds`.
* **training**\
  Contains the last response of the `trainRhasspy` command.
* **updateSentences**\
  Contains the last response ot the `updateSlots` command.`
* **updateSlots**\
  Contains the last response ot the `updateSlots` command.`


## Additionals remarks on MQTT2-IOs
Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see below) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. http://www.steves-internet-guide.com/mosquitto-bridge-configuration/ for the principles). When using MQTT2_CLIENT, it's necessary to set `clientOrder` to include RHASSPY (as most likely, it's the only module listening to the CLIENT). It could be just set to `attr <m2client> clientOrder RHASSPY`\

Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics: `attr <m2client> subscriptions setByTheProgram`\

In case you are using the MQTT server also for other purposes than Rhasspy, you have to set `subscriptions` manually to at least include the following topics additionally to the other subscriptions desired for other purposes:
```
hermes/intent/+
hermes/dialogueManager/sessionStarted
hermes/dialogueManager/sessionEnded
```

## Configure FHEM-devices for use with Rhasspy
To control a device with voice-commands, Rhasspy needs to now some information about the device. It collects this information from the following attributes or from the *genericDeviceType*-attribute.\
Except for *genericDeviceType*, all attribute-names are starting with the prefix used while defining the RHASSPY-device. The following uses the default value *rhasspy*.


**Important**: Be sure to execute `update devicemap` after every change of the following attributes.


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

### Attribute *rhasspyGroup*
Comma-separated "labels" for the groups the device belongs to.

Example:
`attr <device> rhasspyGroup lights`

### Attribute *rhasspyMapping*
If automatic detection of the right intent for a particular type of device isn't working or is not desired, this attribute is used to inform RHASSPY which intents to use to control the device.\
It's possible to assign multiple intents to a single device. Just add one line per mapping.

Example:
```
attr <device> rhasspyMapping SetOnOff:cmdOn=on,cmdOff=off,response="All right"
GetOnOff:currentVal=state,valueOff=off
GetNumeric:currentVal=pct,type=brightness
SetNumeric:currentVal=pct,minVal=0,maxVal=100,map=percent,cmd=pct,step=1,type=brightness
Status:response=The brightness in the kitchen is at [<device>:pct]
MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop,cmdBack=previous,cmdFwd=next
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

### Attribute rhasspyChannels
Used by intent *MediaControls*. Tells the intent, which channels are available and which FHEM-command or perl-code to execute.\
One line per channel.

Example:
```
attr <device> rhasspyChannels orf eins=set <device> channel 201
orf zwei=set <device> channel 202
```

## Intents
Intents are used to tell FHEM what to do after receiving a voice-/text-command. This module has some build-in intents.

### SetOnOff
Intent to turn on/off, open/close, start/stop, ... devices.

Example-Mappings:

`SetOnOff:cmdOn=on,cmdOff=off`\
`SetOnOff:cmdOn=on,cmdOff=off,response="Sir yes Sir"`\
`SetOnOff:cmdOn=on,cmdOff=off,response="$DEVICE now [$DEVICE:state]"`

Arguments:
  * **cmdOn** Command to turn the device on. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).
  * **cmdOff** Command to turn the device off. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).

Optional Arguments:
  * **response** Define a custom response for this mapping

Example-Spoken-Sentences:
  > turn on the light\
  > close the shutter in the bedroom\
  > start the coffee maker
 
 Example-Rhasspy-Sentences:
 ```
 [en.fhem:SetOnOff]
 (turn on|open|start){Value:on) $de.fhem.Device{Device} [$de.fhem.Room{Room}]
 (turn off|close|stop){Value:off} $de.fhem.Device{Device} [$de.fhem.Room{Room}]
 ```
 
### GetOnOff
Intent to request the current state of a device.

Example-Mapping:

`GetOnOff:currentVal=state,valueOff=closed`

Arguments:\
*Hint: only valueOn OR valueOff need to be set. All other values are assigned the other state.*
  * **currentVal** Reading to read the current value from.
  * **valueOff** Value from *currentVal* which represents the **off**-state of the FHEM-device.
  * **valueOn** Value from *currentVal* which represents the **on**-state of the FHEM-device.

Optional Arguments:
  * **response** Define a custom response for this mapping

Example-Sentences:
  > is the light in the bathroom switched on?\
  > is the window in the living room opened?\
  > is the washer running?
  
Example-Rhasspy-Sentences:
```
[en.fhem:GetOnOff]
(is) $de.fhem.Device{Device} [$de.fhem.Room{Room}] (switched on|running|opened){Status}
```

### SetNumeric

Intent to dim, change volume, set temperature, ...

Example-Mappings:
```
SetNumeric:currentVal=pct,cmd=dim,minVal=0,maxVal=99,step=25
SetNumeric:currentVal=volume,cmd=volume,minVal=0,maxVal=99,step=10,type=volume
```
<!--SetNumeric:currentVal=brightness,minVal=0,maxVal=255,map=percent,cmd=brightness,step=1,type=Helligkeit-->

Arguments:
  * **currentVal** Reading which contains the acual value.
  * **part** Used to split *currentVal* into separate values. Separator is a blank. E.g. if *currentVal* is *23 C*, part=1 results in *23*
  * **cmd** Set-command of the device that should be called after analysing the voice-command.
  * **minVal** Lowest possible value
  * **maxVal** Highest possible value
  * **step** Step-size for changes (e.g. *turn the volume up*)
  * **map** Currently only one possible value: percent. See below.
  * **type** To differentiate between multiple possible SetNumeric-Intents for the same device. Currently supports only the following hard-coded values **brightness**, **temperature**, **setTarget**, **volume**, **airHumidity**, **battery**, **waterLevel**, **soilMoisture**

Explanation for `map=percent` or `{Unit:percent}`:
If this option is set, all numeric control values are taken as percentage between *minVal* and *maxVal*.\
If there is a light-device with the setting *minVal=0* and *maxVal=255*, then "turn the light to 50" means the same as "turn the light to 50 percent". The light is then set to 127 instead of 50.-->

Specifics with `type=volume`:
To use the commands *louder* or *lower* without the need to speak a device-name, the module has to know which device is currently playing. Thus it uses the *GetOnOff-Mappings* to search a turned on device with `type=volume`. First it searches in the actual *rhasspyRoom* (the *siteId* or - if missing - the default rhasspyRoom), next in all other *rhasspyRoom*s.\
That's why it's advisable to also set a *GetOnOff*-Mapping if using a *SetNumeric*-Mapping.-->


Example-sentences:
```
Set to light to 30 percent
Turn the radio down
Set the temperature in the living room 2 degree warmer
```

Example-Rhasspy-Sentences:
```
[en.fhem:SetNumeric]
(turn up|increase){Change:volUp} [the volume] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [decibel{Unit}]
(turn down|lower){Change:volDown} [the volume] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [decibel{Unit}]
(turn up|increase){Change:tempUp} [the heating|the temperature] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [degree{Unit}]
(turn down|lower){Change:tempDown} [the heating|the temperature] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [degree{Unit}]
(turn up|increase){Change:lightUp} [the light] [of] $en.fhem.Device{Device} [by] [(0..100){Value}] [percent{Unit:percent}]
(turn down|decrease){Change:lightDown} [the light] [of] $en.fhem.Device{Device} [by] [(0..100){Value}] [percent{Unit:percent}]
```

Currently there are four possible types for `{Change}`:
* tempUp / tempDown
* volUp / volDown
* lightUp / lightDown
* setUp / setDown

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
* **type** To differentiate between multiple possible SetNumeric-Intents for the same device. Currently supports only the german hard-coded values **Helligkeit**, **Temperatur**, **Sollwert**, **Lautstärke**, **Luftfeuchtigkeit**, **Batterie**, **Wasserstand**, **Bodenfeuchte**

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
Status:response="Temperature is [Thermo:temp] degree at [Thermo:hum] percent humidity"
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
MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop,cmdBack=previous,cmdFwd=next
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

Example-Rhasspy-Sentences:
```
[de.fhem:MediaControls]
(start){Command:cmdPlay} the playback [$de.fhem.Device{Device}]
(stop){Command:cmdStop} the playback [$de.fhem.Device{Device}]
(pause){Command:cmdPause} the playback [$de.fhem.Device{Device}]
(next){Command:Fwd} (song|title) [$de.fhem.Device{Device}]
(previous){Command:Back} (song|title) [$de.fhem.Device{Device}] [$de.fhem.Room{Room}]
```

### MediaChannels

Intent to change radio-/tv channels, favorites, playlists, lightscenes, ...

Instead of using the attribute *rhasspyMapping*, this intent is configured with an own attribute **rhasspyChannels** in the respective device. Reason is the multiple-line-configuration.

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
[en.fhem:SetColor]
\[change|color] $de.fhem.Device{Device} [$de.fhem.Room{Room}] $de.fhem.Color{Color}
```

### GetTime

Intent to let Rhasspy speak the actual time.

No FHEM-settings needed.

Example-Sentences:
```
what is the time
tell me the time
```

Example-Rhasspy-Sentences:
```
[en.fhem:GetTime]
(what is|tell me) the time
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

### SetTimer

Intent to create a timer/countdown

This intent creates an AT-command in FHEM with the given time and - currently - speaks the sentences "Timer abgelaufen" when it has expired.

No FHEM-settings needed

Example-Sentences:
```
Set timer in bedroom to five minutes
Set countdown in the kitchen to two hours
```

Example-Rhasspy-Sentence:
```
[de.fhem:SetTimer]
\[set] (timer|countdown) [in] [$de.fhem.Room{Room}] to (1..60){Value} [(minute|minutes|hour|hours|second|seconds){Unit}]
```
Be sure to make the unit optional! Else there is always a random "unit" added to the sentence.

### SetMute

Intent to disable/enable the processing of intents on a specific siteId. Rhasspy will still listen to the wakeword but will not process any intents.

This intents creates a Reading __mute_siteId__ for every siteId it get's a voice-command from.

No FHEM-settings needed

Example-Sentences:
```
good night
be quiet
good morning
make noise
start listening
stop listening
```

Example-Rhasspy-Sentences:
```
[de.fhem:SetMute]
(good night|be quiet){Value:on}
(good morning|make noise){Value:off}
```
Attention! The `{Value:on}` or `{Value:off}` is mandatory, case sensitive and has to be english!

### ReSpeak

Repeats the last sentence, Rhasspy has spoken. To be exactly: Speaks the content of the FHEM-reading `voiceResponse`.

No FHEM-settings needed

Expample-Sentences:
```
what did you say
can you repeat
i did not understand you
```

Example-Rhasspy-Sentences:
```
[de.fhem:ReSpeak]
what did you say
excuse me
can you repeat the last sentence
```


## Custom Intents

It's possible to create custom intents in FHEM's 99_myUtils.pm.

As example an intent that repeats the last voice response Rhasspy has spoken.

Add the following `sub` to your 99_myUtils.pm:
```
sub Respeak(){
    #Credits to JensS
    my $name = "Rhasspy"; #Replace "Rhasspy" with the name of your RHASSPY-Device
    my $response = ReadingsVal($name,"voiceResponse","Sorry, I can not remember my last sentence");
    return $response;
}
```

Then create or edit the attribut `rhasspyIntents` and add the following text. One Intent per line.
```
Respeak=Respeak()
```

Last add a new sentence to sentence.ini of your Rhasspy base:
```
[de.fhem:Respeak]
what did you say
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
- [x] Move IP of Rhasspy-Master to DEF instead of ATTR
- [x] Add Custom intents functionality
- [x] Set-/GetNumeric-Intents multilingual
- [x] Check MediaControls-Intent. Doesn't look functional. And is german-only too.
- [x] Add play and volume SET-functions
- [x] Add timer intent
- [ ] Upgrade timer intent to play WAV file, stop existing timer, use times like "one hour and 15 minutes"
