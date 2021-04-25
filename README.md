# FHEM-rhasspy
[FHEM](https://fhem.de) module for [Rhasspy](https://github.com/rhasspy)

## Contents
[Read First](#Read-First)\
[About Rhasspy](#About-Rhasspy)\
[About FHEM-rhasspy](#About-FHEM-rhasspy)\
[About this repository](#about-this-repository)\
[Installation of FHEM-rhasspy](#Installation-of-FHEM-rhasspy)\
[Additionals remarks on MQTT2-IOs](#additionals-remarks-on-mqtt2-ios)\
[Definition (DEF) in FHEM](#definition-def-in-fhem)\
&nbsp;&nbsp;&nbsp;&nbsp;[Set-Commands (SET)](#set-commands-set)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attributes (ATTR)](#attributes-attr)\
&nbsp;&nbsp;&nbsp;&nbsp;[Readings/Events](#readings--events)\
[Configure FHEM-devices for use with Rhasspy](#configure-fhem-devices-for-use-with-rhasspy)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *genericDeviceType*](#attribute-genericdevicetype)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyName*](#attribute-rhasspyname)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyRoom*](#attribute-rhasspyroom)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyMapping*](#attribute-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyChannels*](#attribute-rhasspychannels)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspyColors*](#attribute-rhasspycolors)\
&nbsp;&nbsp;&nbsp;&nbsp;[Attribute *rhasspySpecials*](#attribute-rhasspyspecials)\
[Intents](#intents)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetOnOff](#setonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetOnOffGroup](#setonoffgroup)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetOnOff](#getonoff)\
&nbsp;&nbsp;&nbsp;&nbsp;[SetNumeric](#setnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetNumeric](#getnumeric)\
&nbsp;&nbsp;&nbsp;&nbsp;[GetState](#getstate)\
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
&nbsp;&nbsp;&nbsp;&nbsp;[Custom Converter to use Real numbers](#custom-converter-to-use-real-numbers)\
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

FHEM-rhasspy evaluates parts of the MQTT traffic, converts these JSON-messages to commands and also sends messages to Rhasspy to e.g. provide responses on commands as TextToSpeech.

FHEM-rhasspy uses the 00_MQTT2_CLIENT.pm module to receive and send these messages. Therefore it is necessary to define an MQTT2_CLIENT device in FHEM before using FHEM-rhasspy.

fhem-rhasspy is based on the [Snips-Module](https://github.com/Thyraz/Snips-Fhem). Thanks to Thyraz, who did all the groundwork with his!

## About this repository

This repository contains all files to set up a complete installation to test Rhasspy and FHEM with Docker under Windows using the Windows Subsystem for Linux (WSL).

## Installation of FHEM-rhasspy
- Update FHEM
- Download a RAW-Copy of 10_RHASSPY.pm and copy it to your FHEM directory (in most cases `opt/fhem/FHEM`)
- Don't forget to change the ownership of the file to `fhem:dialout` (or whatever user/group FHEM is using)
- Define a MQTT2_CLIENT device which connects to the MQTT-server Rhasspy is using. E.g.:
```
define <deviceName> MQTT2_CLIENT <ip-or-hostname-of-mqtt-server>:<port> 
```
- Change the `clientOrder` to set the right notification order:
```
attr <deviceName> clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE
```
- Add MQTT-subscriptions needed for this module:
```
attr <deviceName> subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded
```

**Important**: The attribute `clientOrder` ist not available in older version of MQTT2_CLIENT. Be sure to use an up-to-date version of this module.

## Additionals remarks on MQTT2-IOs
Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see below) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. http://www.steves-internet-guide.com/mosquitto-bridge-configuration/ for the principles). When using MQTT2_CLIENT, it's necessary to set `clientOrder` to include RHASSPY (as most likely, it's the only module listening to the CLIENT). It could be just set to `attr <m2client> clientOrder RHASSPY`

Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics: `attr <m2client> subscriptions setByTheProgram`

In case you are using the MQTT server also for other purposes than Rhasspy, you have to set `subscriptions` manually to at least include the following topics additionally to the other subscriptions desired for other purposes:
```
hermes/intent/+
hermes/dialogueManager/sessionStarted
hermes/dialogueManager/sessionEnded
```

## Definition (DEF) in FHEM
You can define a new instance of this module with:

```
define <name> RHASSPY <baseUrl> <devspec> <defaultRoom> <language> <fhemId> <prefix> <useGenericAttrs> <encoding>
```

All parameters are optional but changing some of them later may result in confusing results. So it's recommended to especially check if _fhemId_ and/or _prefix_ really have to be set different than the defaults. In most cases, these two are for advanced configuration (e.g. multiple languages), so when starting with RHASSPY, you may not care much about that.

* **`baseUrl`**\
  The url of the Rhasspy service web-interface. If using a base and multiple satellites, use the url of the base. Make sure, this is set to correct values (IP and Port)! Default is `baseUrl=http://127.0.0.1:12101`.

* **`devspec`**\
  [devspec](https://commandref.fhem.de/commandref.html#devspec) of the device(s) that should be controlled with Rhasspy. For backwards compability, default is `devspec=room=Rhasspy`, but you may use e.g. just a comma separated list of devices you want to interact with Rhasspy. Without a match to devspec, no device can interact with RHASSPY, regardless if you set any of the further attributes to configure them.

* **`defaultRoom`**\
  Name of the default room which should be used if no room-name is present in the command and no suitable room can be found for the device. Default is `defaultRoom=default`.

* **`language`**\
  Language of the voice commands spoken to Rhasspy. Default is derived from _global_-device, which defaults to `language=en`.

* **`fhemId`**\
  Used to differ between multiple instances of RHASSPY on the MQTT side. Also is a part of the topic tree the corresponding RHASSPY is listening to. Default is `fhemId=fhem`.

* **`prefix`**\
  Used to differ between multiple instances of RHASSPY on the FHEM-internal side. Usefull, if you have several instances of RHASSPY in one FHEM running and want e.g. to use different identifier for groups and rooms (e.g. a different language). Default is `prefix=rhasspy`.

* **`useGenericAttrs`**\
  By default, RHASSPY - beside it's own attributes - uses the general _genericDeviceType_ attribute (which is also used by other voice command solutions) to identifiy the control-features of the devices you want to command. This option adds the attribute `genericDeviceType` to the _global_ attribute list. If you are not happy with the results _genericDeviceType_ provides, you may replace them by setting appropriate values in _rhasspyMapping_. Set this to zero, if you want to deactivate this feature: `useGenericAttrs=0`.

* **`encoding`**\
  If there are any problems with mutated vowels it's possible to set a specific character encoding. Default is _none_ which in most cases is UTF-8.



Simple-Example for a define:
```
define Rhasspy RHASSPY
```

Full-Example for a define:
```
define Rhasspy RHASSPY baseUrl=http://192.160.2.122:12101 devspec=genericDeviceType=.+ defaultRoom=wohnzimmer language=de fhemId=fhem1 prefix=rhasspy2 useGenericAttrs=0 encoding=cp-1252
```


### Set-Commands (SET)
* **customSlot**\
  Creates a new - or overwrites an existing slot - in Rhasspy\
  Provide slotname, slotdata and (optional) info, if existing data shall be overwritten and training shall be initialized immediately afterwards.\
  First two arguments are required, third and fourth are optional.\
  `overwrite` defaults to true, setting any other value than true will keep existing Rhasspy slot data.\

  Examples:\
  `set <rhasspyDevice> customSlot mySlot a,b,c overwrite training`\
  `set <rhasspyDevice> customSlot slotname=mySlot slotdata=a,b,c overwrite=false`
* **fetchSiteIds**\
  Fetch all available siteIds from Rhasspy-Base and create a reading _siteIds_. Used for e.g. to determine on which Rhasspy satellite the user gets informed that a timer has ended.\
  Has to be executed everytime a new satellite is installed or a new siteId is added to Rhasspy.
  Example: `set <rhasspyDevice> fetchSiteIds`
* **play**\
  Send a WAV file to Rhasspy.\
  `siteId` and `path` are required!\
  You may optionally add a number of repeats and a wait time in seconds between repeats. wait defaults to 15, if only repeats is given.\
  Examples:\
  `set <rhasspyDevice> play siteId="default" path="/opt/fhem/test.wav"`\
  `set <rhasspyDevice> play siteId="default" path="./test.wav" repeats=3 wait=20`
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

* **update**
  * **devicemap**\
    When the configuration work to RHASSPY and all subordinated devices is finished or there had been changes, issuing a devicemap-update is mandatory, to get the RHASSPY data structure updated, inform Rhasspy on changes that may have occured (update slots) and initiate a training on updated slot values etc.
    Has to be executed after changes to the attributes of a Rhasspy-controlled devices or the RHASSPY device itself.\
    Example: `set <rhasspyDevice> update devicemap`
  * **devicemap_only**\
    Used to check whether attribute changes have found their way to the data structure. This will neither update slots nor initiate any training towards Rhasspy.\
    Example: `set <rhasspyDevice> update devicemap_only`
  * **slots**\
    Sends a command to the HTTP-API of the Rhasspy master to update all slots on Rhasspy with actual FHEM-devices, rooms, etc.\
    Updated/Created Slots are
    - en.fhem.AllKeywords
    - en.fhem.Device
    - en.fhem.Device-*genericDeviceType*
    - en.fhem.Group
    - en.fhem.Room
    - en.fhem.MediaChannels
    - en.fhem.Color
    - en.fhem.NumericType
   
    Example: `set <rhasspyDevice> update slots`
  * **slots_no_training**\
    Same as `slots` without starting a training after updating.\
    Example: `set <rhasspyDevice> update slots_no_training`
  * **language**\
    Reinitialization of language file.\
    Be sure to execute this command after changing something in the language-configuration files or the attribute `configFile`!\
    Example: `set <rhasspyDevice> update language`
  * **all**\
    Update devicemap and language.\
    Example: `set <rhasspyDevice> update all`
* **volume**\
    Sets volume of given siteId between 0 and 1 (float)\
    Both arguments (siteId and volume) are required!\
    Example: `set <rhasspyDevice> siteId="default" volume="0.5"`


**Do not forget to issue an `update devicemap` after making any changes to Rhasspy-controlled devices or the RHASSPY-device itself!**

### Attributes (ATTR)
* **IODev**\
  The MQTT2_CLIENT device FHEM-rhasspy is connected to.
  Example: `attr <rhasspyDevice> IODev rhasspyMQTT2`
* **configFile**\
  Path to the language-config file.\
  If this attribute isn't set, english is used for voice responses.
  
  The file itself must contain a JSON-encoded keyword-value structure following the given structure for the mentioned english defaults. As a reference, there is a german language file available. Or it's possible to make a dump of the english structure (with e.g.: `{toJSON($defs{RHASSPY}->{helper}{lng})}`; replace RHASSPY by your device's name). Create a new file and edit this results as desired. There might be some variables to be used - these should also work in your sentences.\
  configFile also allows combining a default set of e.g. german sentences with some few own modifications by using "defaults" subtree for the defaults and "user" subtree for your modified versions. This feature might be helpful in case the base language structure has to be changed in the future.
  
  Example: `attr <rhasspyDevice> configFile ./.config/rhasspy/rhasspy-de.cfg`
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
  * DATA => entire JSON-$data (as parsed internally, JSON-encoded)
  * siteId, Device etc. => any element out of the JSON-$data

  If a simple text is returned, this will be considered as response.\
  For more advanced use of this feature, you may return an array. First element of the array will be interpreted as comma-separated list of devices that may have been modified (otherwise, these devices will not cast any events! See also the "d" parameter in *rhasspyShortcuts*). The second element is interpreted as response and may either be simple text or HASH-type data. This will keep the dialogue-session open to allow interactive data exchange with Rhasspy. An open dialogue will be closed after some time, default is 20 seconds, you may alternatively hand over other numeric values as third element of the array.

* **rhasspyShortcuts**\
  Define custom sentences without editing Rhasspy sentences.ini.\
  The shortcuts are uploaded to Rhasspy when using the `update slots` (or `update devicemap`) set-command.\
  One shortcut per line, syntax is either a simple or an extended version.\
  Examples:
  ```
  mute on=set amplifier mute on
  mute off={fhem("set amplifier mute off")}
  i="turn dark" f="set bulb1 off" d="bulb1"
  i="turn bright" f="set bulb1 on" d="bulb1"
  i="let it be day" p={fhem ("set $NAME on")} d="bulb01"
  i="let it be night" p={fhem ("set $NAME off")} d="bulb01"
  i="make noise" f="set Rhasspy speak siteId='livingroom' text='wuff wuff'" r=""
  i="do the cooking" f="set bulb01 on" d="blub01" c="do you want pizza?"
  i="when does the sun rise" r="um [Astro:SunRise] uhr"
  i="when does the sun set" r="um [Astro:SunSet] uhr"
  ```

  Abbreviations explanation:
  * **i**: intent\
    Lines starting with `i=` will be interpreted as extended version, so if you want to use that syntax style, starting with `i=` is mandatory.
  * **f**: FHEM command\
    Syntax as usual in FHEMWEB command field.
  * **p**: perl command\
    Syntax as usual in FHEMWEB command field, enclosed in {}; this has priority to `f=`.
  * **d**: device name(s)\
    Device name(s, comma separated) that will be handed over to fhem.pl as updated devices. Needed for triggering further actions and longpoll! If not set, the return value of the called function will be used.
  * **r**: response\
    Response to be send to the caller. If not set, the return value of the called function will be used.\
    Response sentence will be parsed to do "set magic"-like replacements, so also a line like `i="what's the time for sunrise" r="at [Astro:SunRise] o'clock"` is valid.
	You may ask for confirmation as well using the following (optional) shorts:
    * **c**: Confirmation request: Command will only be executed, when separate confirmation is spoken. Value _c_ is either numeric or text. If numeric: Timeout to wait for automatic cancellation. If text: response to send to ask for confirmation.
    * **ct**: Numeric value for timeout in seconds, default: 15

* **rhasspyTweaks**\
  Currently sets additional settings for timers and slot-updates to Rhasspy. May contain further custom settings in future versions like siteId2room info or code links, allowed commands, confirmation requests etc.\
  Could be the place to configure additional things like additional siteId2room info or code links, allowed commands, duration of SetTimer sounds, confirmation requests etc.\
  * **timerLimits**\
    See intent [SetTimer](#settimer)
  * **timerSounds**\
    You may play (and repeat) WAV files instead of default one-time spoken info, when timer is ending. See intent [SetTimer](#settimer)
  * **updateSlots**\
    Changes aspects on slot generation and updates.
    
    `noEmptySlots=1`
    By default, RHASSPY will generate an additional slot for each of the genericDeviceType it recognizes, regardless, if there's any devices marked to belong to this type. If set to 1, no empty slots will be generated.

    `overwrite_all=false`
    By default, RHASSPY will overwrite all generated slots. Setting this to false will change this.


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


## Configure FHEM-devices for use with Rhasspy
To control a device with voice-commands, Rhasspy needs to now some information about the device. It collects this information from the *genericDeviceType*-attribute or from special attributes.\
Except for *genericDeviceType*, all attribute-names are starting with the prefix used while defining the RHASSPY-device.\
This documentation uses the default prefix *rhasspy*.


**Important**: 
* Be sure to execute `update devicemap` everytime after changing one of the following attributes - otherwise neither RHASSPY nor Rhasspy will know the changed values
* RHASSPY will consolidate all information given in the attributes in it's own device hash. Use _list_ command to see result of the consolidation process initiated by the `update devicemap` command. All names and other "labels" are converted to lower case, so make sure, Rhasspy is also delivering lower case values when filling slots manually.
* Minimum requirements for a FHEM device to work with RHASSPY are:\
  * Device has to match devspec
  * at least one of the following attributes has to be set in the device (basically, genericDeviceType or one of the RHASSPY-specific mapping attributes).
* mapping logic generally is as follows:
  * if RHASSPY-specific attributes are provided, only the value of this attribute will **exclusively** be used (obviously: only for the purpose of the specific attribute, so e.g. setting _rhasspyName_ will not prevent analysis of _genericDeviceType_ possibilities to set the device _on_ or _off_ or it's _brighness_).   
  * the more specific attribute values will override the less specific ones. So, (if no _rhasspyName_ is set) _alias_ will prevent using (technical) _device name_ to be used, and having set _alexaName_ will result in (to some extend exclusive) use of the values set there. If two possibilities are on the same "specific level" (e.g. _alexaName_ and _siriName_ are set), both will be used.  
* attribute values typically are typically read "line by line", following the general rule "one topic per line". So make sure to set newline marks at the right places

### Attribute genericDeviceType

If `useGenericAttrs` in the DEF is set to "1" (which is the default), RHASSPY will try to determine mapping (and other) information from the attributes already present (if devices match devspec). Currently the following subset of _genericDeviceType_ is supported:

* switch
* light
* thermostat
* thermometer
* blind
* media

When using _genericDeviceType_, collected information about the device are for example:
* the name (NAME or alias)
* the ROOM or GROUP the device is in
* how to GET information from the device
* how to SET state/values

This is the easiest way to get devices to work with RHASSPY. In some cases it may happen that _gDT_ delivers to less or not suitable information for this particual device. Then it's possible to overwrite this with the following RHASSPY specific device attributes.

### Attribute *rhasspyName*
The content of this attribute is the name you want to call this device (e.g. *bulb*). It's possible to use multiple names for the same device by separating them with comma.\
Example:
```
attr <device> rhasspyName bulb,leiling light,chandelier
```
It's also possible to have the same name for different FHEM-devices. Just make sure they are located in different _rooms_ (e.g. by setting the *rhasspyRoom* attribute).

### Attribute *rhasspyRoom*
You can add an attribute `rhasspyRoom` to the device to tell Rhasspy in which physical (or logical) room the device is. If omitted, (alexaRoom or) standard FHEM _room_ attribute is used. If this is also not provided, it belongs to the "default room" as set in _define_\
This is useful to speak commands without a room. If there is a device *bulb* and it's *rhasspyRoom*-attribute is equal to the siteId of your satellite, it's enough to say "Bulb on" and the bulb in the room the command is spoken will be turned on.
`rhasspyRoom` also accepts a comma-separated list.

Example:
```attr <device> rhasspyRoom livingroom```

### Attribute *rhasspyGroup*
Comma-separated "labels" for the groups the device belongs to.

Example:
`attr <device> rhasspyGroup lights,worktop illumination,kitchen illumination`


### Attribute *rhasspyMapping*
If automatic detection of the right intent for a particular type of device isn't working or is not desired, this attribute is used to inform RHASSPY which intents to use to control the device.\
It's possible to assign multiple intents to a single device. Just add one line per mapping.

Example:
```
attr <device> rhasspyMapping SetOnOff:cmdOn=on,cmdOff=off,response="All right"
GetOnOff:currentVal=state,valueOff=off
GetNumeric:currentVal=pct,type=brightness
SetNumeric:currentVal=brightness,cmd=brightness,minVal=0,maxVal=255,map=percent,step=1,type=brightness
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

### Attribute rhasspyChannels
Used by intent *MediaControls*. Tells the intent, which channels are available and which FHEM-command or perl-code to execute.\
One line per channel.

To use **rhasspyChannels** you have to first create a new user-attribute on the FHEM-device you want to control. You can do this for example with the following command:
```
attr <deviceName> userattr rhasspyChannels:textField-long
```

Example:
```
attr <device> rhasspyChannels orf eins=channel 201
orf zwei=channel 202
orf drei=channel 203
```

### Attribute rhasspyColors
Used to change to colors of a light\

To use **rhasspyColors** you have to create this user-attribute first with e.g.:
```
attr <deviceName> userattr rhasspyChannels:textField-long
```

key=value line by line arguments mapping keys to setter strings on the same device.

Example:
```
attr lamp1 rhasspyColors red=rgb FF0000
green=rgb 008000
blue=rgb 0000FF
yellow=rgb FFFF00
```

### Attribute rhasspySpecials
key=value line by line arguments similar to rhasspyTweaks\
Currently only group related stuff is implemented, this could be the place to hold additional options, e.g. for confirmation requests.

Example:
```
attr lamp1 rhasspySpecials group:async_delay=100 prio=1 group=lights
```

Explanation on the above group line. All arguments are optional:

* **group**
  If set, the device will not be directly addressed, but the mentioned group - typically a FHEM structure device or a HUEDevice-type group. This has the advantage of saving RF ressources and/or already implemented logics.\
  Note: all addressed devices will be switched, even if they are not member of the rhasspyGroup. Each group should only be addressed once, but it's recommended to put this info in all devices under RHASSPY control in the same external group logic.
* **async_delay**
  Float nummeric value, just as async_delay in structure; the delay will be obeyed prior to the next sending command.
* **prio**
  Numeric value, defaults to "0". prio and async_delay will be used to determine the sending order as follows: first devices will be those with lowest prio arg, second sort argument is async_delay with lowest value first


## Intents
Intents are used to tell FHEM what to do after receiving a voice-/text-command. This module has some build-in intents.

### SetOnOff
Intent to turn on/off, open/close, start/stop, ... devices.

Example-Mappings:
```
SetOnOff:cmdOn=on,cmdOff=off
SetOnOff:cmdOn=on,cmdOff=off,response="Sir yes Sir"
SetOnOff:cmdOn=on,cmdOff=off,response="$DEVICE now [$DEVICE:state]"
```

Arguments:
  * **cmdOn** Command to turn the device on. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).
  * **cmdOff** Command to turn the device off. See [Formatting Commands and Readings inside a *rhasspyMapping*](#formatting-commands-and-readings-inside-a-rhasspymapping).

Optional Arguments:
  * **response** Define a custom response for this mapping

Example-Sentences:
  > turn on the light\
  > close the shutter in the bedroom\
  > start the coffee maker
 
Example-Rhasspy-Sentences:
```
[en.fhem:SetOnOff]
(turn on|open|start){Value:on) $de.fhem.Device{Device} [$de.fhem.Room{Room}]
(turn off|close|stop){Value:off} $de.fhem.Device{Device} [$de.fhem.Room{Room}]
```

Required tags:
* Value:on and/or Value:off
* Device

Optional tags:
* Room

### SetOnOffGroup
Intent to switch a group of devices.

SetOnOff-Mapping needed and all desired devices have to have the attribut **rhasspyGroup** configured.

Example-Sentence:
  > turn off all lights in the kitchen
  > close all blinds in the sleeping room
  > turn on all lights

Example-Rhasspy-Sentences:
```
[en.fhem:SetOnOffGroup]
(turn on|open){Value:on} all $de.fhem.Group{Group} (:){Room:global}([$en.fhem.Room{Room}])
(turn off|close){Value:off} all $de.fhem.Group{Group} (:){Room:global}([$de.fhem.Room{Room}])
```

Required tags:
* Value:on and/or Value:off
* Group

Optional tags:
* Room
 
### GetOnOff
Intent to request the current state of a device.

Example-Mappings:

`GetOnOff:currentVal=state,valueOff=closed`
`GetOnOff:currentVal=state,valueOn=on`
`GetOnOff:currentVal=pct,valueOff=0`

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
(is) $de.fhem.Device{Device} [$de.fhem.Room{Room}] (switched on|running|opened){State:on}
(is) $de.fhem.Device{Device} [$de.fhem.Room{Room}] (switched off|stopped|closed){State:off}
```

Be sure to split on- and off-states into different sentences including *{State:on}* and *{State:off}*

Required tags:
* State:on and/or State:off
* Device

Optional tags:
* Room

### SetNumeric

Intent to dim, change volume, set temperature, ...

Example-Mappings:
```
SetNumeric:currentVal=pct,cmd=dim,minVal=0,maxVal=99,step=25,type=brightness
SetNumeric:currentVal=volume,cmd=volume,minVal=0,maxVal=99,step=10,type=volume
SetNumeric:currentVal=brightness,cmd=brightness,minVal=0,maxVal=255,map=percent,step=1,type=brightness
```

Arguments:
  * **currentVal** Reading which contains the acual value. Required.
  * **part** Used to split *currentVal* into separate values. Separator is a blank. E.g. if *currentVal* is *23 C*, part=0 results in *23*. Optional.
  * **cmd** Set-command of the device that should be called after analysing the voice-command. Required.
  * **minVal** Lowest possible value. Optional.
  * **maxVal** Highest possible value. Optional.
  * **step** Step-size for changes (e.g. *turn the volume up*). Optional. Default 10.
  * **map** Currently only one possible value: percent. See below. Optional.
  * **type** To differentiate between multiple possible SetNumeric-Intents for the same device. Recommended.

Explanation for `map=percent` or `{Unit:percent}`:
If on of these options is set, all numeric control values are taken as percentage between *minVal* and *maxVal*.\
If there is a light-device with the setting *minVal=0* and *maxVal=255*, then "turn the light to 50" means the same as "turn the light to 50 percent". The light is then set to 127 instead of 50.

Good to know:\
To use the commands like *louder* or *lower* without the need to speak a device-name, the module has to know which device is currently playing. Thus it uses the *GetOnOff-Mappings* to search a turned on device with e.g. `type=volume`. First it searches in the actual *rhasspyRoom* (as indicated in RHASSPY list, this is not restricted to the attribute!) (the *siteId* or - if missing - the default rhasspyRoom), next in all other *rhasspyRoom*s.\
That's why it's advisable to also set a *GetOnOff*-Mapping if using a *SetNumeric*-Mapping.

Possible **type**s:
* **brightness**
* **setTarget**
* **temperature**
* **volume**

Example-sentences:
```
Set to light to 30 percent
Turn the radio down
Set the temperature in the living room 2 degree warmer
```

Example-Rhasspy-Sentences:\
(if you need to speak Real numbers ("two point five") see [Custom Converter to use Real numbers](#custom-converter-to-use-real-numbers))
```
[en.fhem:SetNumeric]
(change) $de.fhem.Device{Device} [$de.fhem.Room{Room}] to (0..100){Value!int} [percent{Unit:percent}]
(turn up|increase){Change:volUp} [the volume] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [decibel{Unit}]
(turn down|lower){Change:volDown} [the volume] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [decibel{Unit}]
(turn up|increase){Change:tempUp} [the heating|the temperature] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [degree{Unit}]
(turn down|lower){Change:tempDown} [the heating|the temperature] [of] $en.fhem.Device{Device} [by] [(0..10){Value!float}] [degree{Unit}]
(turn up|increase){Change:lightUp} [the light] [of] $en.fhem.Device{Device} [by] [(0..30 [point:. 1..9]){Value!customFloat}] [percent{Unit:percent}]
(turn down|decrease){Change:lightDown} [the light] [of] $en.fhem.Device{Device} [by] [(0..30 [point:. 1..9]){Value!customFloat}] [percent{Unit:percent}]
```

Currently there are this possible types for tag `{Change}`:
* tempUp / tempDown
* volUp / volDown
* lightUp / lightDown
* setUp / setDown

Required tags:
* Change or Type
* Value or Change

Optional tags:
* Device
* Room
* Unit

### GetNumeric

Intent to question values like actual temperature, brightness, volume, ...

Example-Mappings:
```
GetNumeric:currentVal=temperature,part=1,type=temperature
GetNumeric:currentVal=pct,map=percent,minVal=0,maxVal=100,type=brightness
GetNumeric:currentVal=volume,type=volume
GetNumeric:currentVal=humidity,part=0,type=airHumidity
GetNumeric:currentVal=batteryPercent,type=battery
```

Arguments:
* **currentVal** Reading which contains the value.
* **part** Used to split *currentVal* into separate values. Separator is a blank. E.g. if *currentVal* is *23 C*, part=1 results in *23*
* **map** See Explanation in [SetNumeric Intent](#setnumeric). Converts the given value back to a percent-value.
* **minVal** Lowest possible value. Only needed if *map* is used.
* **maxVal** Highest possible value. Only needed if *map* is used.
* **type** To differentiate between multiple possible SetNumeric-Intents for the same device.

Possible **type**s:
* **airHumidity**
* **battery**
* **brightness**
* **desired-temp**
* **setTarget**
* **soilMoisture**
* **temperature**
* **volume**
* **waterLevel**

Example-Sentences:
```
what is the temperature in the living room
how bright is the floor lamp
what is the volume of the tv
```

Example-Rhasspy-Sentences:
```
[en.fhem:GetNumeric]
#actual temperature
(what is|how high is) the temperature{Type:temperature} [$en.fhem.Device{Device}] [$en.fhem.Room{Room}]

#desired-temperature
\[what is the|how high is the] (desired temperature){Type:desired-temp} [($en.fhem.Device){Device}] [$en.fhem.Room{Room}]

#volume
(what is the|how high is the) volume{Type:volume} $en.fhem.Device{Device} [$en.fhem.Room{Room}]
```

Required tags:
* Device
* Type

Optional tags
* Room

### GetState

Intent to get specific information of a device. The respone can be defined.

Example-Mappings:
```
GetState:response="Temperature is [$DEVICE:temp] degree at [Thermo:hum] percent humidity"
GetState:response={my $value=ReadingsVal("$DEVICE","brightness",""); return "Brightness is $value";}
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
[de.fhem:GetState]
\[how is the] (state) $de.fhem.Device{Device} [$de.fhem.Room{Room}]
```

Required tags:
* Device

Optional tags:
* Room

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

Required tags:
* Command

Optional tags:
* Device
* Room

### MediaChannels

Intent to change radio-/tv channels, favorites, playlists, lightscenes, ...

Instead of using the attribute *rhasspyMapping*, this intent is configured with an own attribute **rhasspyChannels** in the respective device. Reason is the multiple-line-configuration.

Example-Mappings:
```
SWR3=favorite s_w_r_3
SWR1=favorite s_w_r_1
ARD=channel 204
Netflix=launchApp Netflix
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
[en.fhem:MediaChannels]
\[(play|switch to|change to)] ($de.fhem.MediaChannels){Channel} [($de.fhem.Device){Device}] [($de.fhem.Room){Room}]
```

Required tags:
* Channel

Optional tags:
* Device
* Room

### SetColor

Intent to change light colors

Because of the multi-line settings, instead of configuring this intent with the attribute *rhasspyMapping*, a separate user-attribute *rhasspyColors* is used.

The content of the *rhasspyColors* uses the following format:\
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

Required tags:
* Color
* Device

Optional tags
* Room

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

No FHEM-settings needed.

Example-Sentences:
```
which weekday is today
```

Example-Rhasspy-Sentences:
```
[en.fhem:GetWeekday]
which weekday is today
```

### SetTimer

Intent to create a timer/countdown/alarm

This intent creates an AT-command in FHEM with the given time and - currently - speaks the sentences "timer expired" when it has expired.

No FHEM-settings needed

Example-Sentences:
```
Set timer in bedroom to five minutes
Set countdown in the kitchen to two hours
set timer to five and a half hours
set alarm to 5 o' clock
set timer to 3 hours and 20 minutes
set timer to 1 hour, 30 minutes and 15 seconds
stop the timer in bedroom
```

Example-Rhasspy-Sentence:
```
[en.fhem:SetTimer]
labels=(alarm|teetimer|countdown|timer)
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in) [((1..60){Hour!int} (hour|hours))] [and] [((1..60){Min!int} (minute|minutes))] [and] [((1..60){Sec!int} (second|seconds))]
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in) (1..60){Hour!int} and (a quarter{Min:15}|a half{Min:30}|three quarters{Min:45}) (hour|hours)
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in) (1..60){Min!int} and (a quarter{Sec:15}|a half{Sec:30}|three quarters{Sec:45}) (minute|minutes)
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in) ((the fourth){Min:15}|(half a){Min:30}|(three fourth){Min:45}) (hour)
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in) ((the fourth){Min:15}|(half a){Min:30}|(three fourth){Min:45}) (minute)
\[<labels>{Label}] [$en.fhem.Room{Room}] (to|in|at) (1..24){Hourabs!int} [(1..60){Min!int}] o clock

(cancel|remove|stop|delete){CancelTimer} [<labels>{Label}] [$en.fhem.Room{Room}]
```

Required tags to set a timer:
* Label
* On of Hour, Hourabs, Min, Sec

Required tags to cancel a timer:
* Label

#### rhasspyTweaks for Timer
* **timerLimits**\
  Used to determine when the timer should response with e.g. "set to 30 minutes" or with "set to 10:30"\

  Example:
  ```
  timerLimits=90,300,3000,2*HOURSECONDS,50
  ```
* **timerSounds**\
  Per default the timer responds with a voice command if it has elapsed. If you want to use a wav-file instead, you can set this here.

  All five values have to be set, corresponding with the limits to *timerSet* responses.\
  Following example will lead to seconds response for less then 90 seconds, minute+seconds response for less than 300 seconds etc.. Last value is the limit in seconds, if timer is set in time of day format.

  Example:
  ```
  timerSounds= default=./yourfile1.wav eggs=3:20:./yourfile2.wav potatoes=5:./yourfile3.wav
  ```

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
can you [please] repeat the last sentence
```


## Custom Intents

It's possible to create custom intents in FHEM's 99_myUtils.pm.

As example an intent that repeats the last voice response Rhasspy has spoken.

Add the following `sub` to your 99_myUtils.pm:
```perl
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

### Custom Converter to use Real numbers

Rhasspy is (currently) not able to recognize spoken Real numbers (e.g. ten point five) as numbers. Instead it interprets them as two numbers and "point".\
To use Real numbers correctly, you have to create a custom converter and use this in your sentences.\

To do this, create a file under <rhasspy-profile>/converters, name it as you wish and make it executable.\
E.g.
```
> touch .config/rhasspy/profile/en/converters/customFloat
> chmod +x .config/rhasspy/profile/en/converters/customFloat
```

Then fill it with the following example-code:
```python
#!/usr/bin/env python3
import sys
import json

# [22, ".", 5]
args = json.load(sys.stdin)

# 22.5
num = "".join(str(s).strip() for s in args)

print(num)
```

Restart Rhasspy and afterwards you can use your custom-converter in your sentences.
```
[SetHeating]
set heating [to] (0..30 [point:. 0..99]){temp!customFloat}
```


### Rhasspy speaks actual state of device after switching it

JensS wrote a short script to let Rhasspy speak the actual state of a FHEM-device after switching it with a voice-command.\
Add the following to your 99_myUtils.pm

```perl
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
- [ ] Check and document possibilites of *response* in mappings
- [ ] As soon as rhasspyName is defined, FHEM-room is ignored? (needs confirmation) (Beta-User: not intended, but rhasspyRoom should override FHEM-room) 
- [x] Upgrade timer intent to play WAV file, stop existing timer, use times like "one hour and 15 minutes"
- [x] Move IP of Rhasspy-Master to DEF instead of ATTR
- [x] Add Custom intents functionality
- [x] Set-/GetNumeric-Intents multilingual
- [x] Check MediaControls-Intent. Doesn't look functional. And is german-only too.
- [x] Add play and volume SET-functions
- [x] Add timer intent
