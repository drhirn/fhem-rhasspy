##############################################
# $Id: myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.

package main;

use strict;
use warnings;

sub
myUtils_Initialize($$)
{
  my ($hash) = @_;
}

# Enter you functions below _this_ line.

sub ResponseOnOff{
  my $dev = shift // return;
  my $room;
  my $state = lc(ReadingsVal($dev,'state','im unbekannten Status'));
  my $name = (split(/,/,AttrVal($dev,'rhasspyName','error')))[0];
  if (AttrVal($dev,'rhasspyRoom',"")){$room = ' im '.(split(/,/,AttrVal($dev,'rhasspyRoom',"")))[0]};
  $state=~s/.*on/eingeschaltet/;
  $state=~s/.*off/ausgeschaltet/;
  return "Ok - ".$name.$room." ist ".$state
}

sub rhasspyCalc{
  my $val1 = shift // return;
  my $val2 = shift // return;
  my $op = shift // return;

  my $response = "Dafür muss ich nochmal in die Nachhilfe";

  if ($op eq "plus") {
    $response = "Das Ergebnis ist " . ($val1 + $val2);
  }

  if ($op eq "minus") {
    $response = "Das Ergebnis ist " . ($val1 - $val2);
  }

  if ($op eq "mul") {
    $response = "Das Ergebnis ist " . ($val1 * $val2);
  }

  if ($op eq "div") {
    $response = "Das Ergebnis ist " . ($val1 / $val2);
  }

  $response =~ s/\./,/ig;
  return $response;
}

1;
