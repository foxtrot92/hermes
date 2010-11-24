#
# Copyright (c) 2008 Klaas Freitag <freitag@suse.de>, Novell Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
################################################################
# Contributors:
#  Klaas Freitag <freitag@suse.de>
#
package Hermes::MessageSender;

use strict;
use Exporter;

use Data::Dumper;

use Hermes::Config;
use Hermes::DB;
use Hermes::Log;
use Hermes::Util;
use Hermes::Delivery::Mail;
use Hermes::Delivery::RSS;
use Hermes::Delivery::Http;
use Hermes::Delivery::Twitter;
# use Hermes::Delivery::Jabber;
use Hermes::Person;
use Hermes::Message;
use Hermes::Customize;

use HTML::Template;

use vars qw(@ISA @EXPORT $query );

#
# This is the general query used by the most sending methods here. It is prepared and 
# stored in a module global variable, which only causes trouble if its used multiple 
# times.
#
use constant SQL => scalar "SELECT gn.id, gn.notification_id, gn.created_at, subs.id, \
 subs.msg_type_id, subs.person_id, subs.delay_id, subs.delivery_id FROM \
 generated_notifications gn\
 JOIN subscriptions subs ON subs.id = gn.subscription_id\
 WHERE gn.sent = 0 AND subs.enabled=1 AND subs.delay_id=?\
 ORDER BY subs.id, gn.created_at DESC LIMIT ?";

@ISA	    = qw(Exporter);
@EXPORT	    = qw( sendMessageDigest sendImmediateMessages );


######################################################################
# sub markSent
# -------------------------------------------------------------------
# Marks the message with the given ID as sent.  Returns true on
# success and false on failure.
######################################################################

sub markSent( $ )
{
  my ($notiIds) = @_;

  my $sql = 'UPDATE LOW_PRIORITY generated_notifications SET sent = NOW() WHERE id = ?';
  my $sth = dbh()->prepare( $sql );

  my $res = 0;

  if( ref $notiIds eq "ARRAY" ) {
    foreach my $id ( @$notiIds) {
      my $logMsg = "set generated_notification id <$id> to sent!";
      if( $Hermes::Config::Debug > 0 && $Hermes::Config::Debug != 2 ) {
	$logMsg = "DEBUG - SKIPPED: " . $logMsg;
      } else {
	$res += $sth->execute( $id );
      }
      log( 'notice', $logMsg );
    }
  } else { # Assume that it is a scalar id from sendImmediate
    my $logMsg = "set generated_notification id <$notiIds> to sent!";
    $logMsg .= " + Debug: " . $Hermes::Config::Debug;
    if( $Hermes::Config::Debug > 0 && $Hermes::Config::Debug != 2 ) {
      $logMsg = "DEBUG - SKIPPED: " . $logMsg;
    } else {
      $res = $sth->execute( $notiIds );
    }
    log( 'info', $logMsg );
  }
  return ($res > 0);
}


=head1 NAME

sendMessageDigest() - sends a digest of queued messages

=head1 SYNOPSIS

    use Hermes::MessageSender;

    my $delay = SEND_HOURLY;	# Send messages queued for hourly distribution.
    my $type = 'test';		# Send messages of the 'test' type.

    my $count = sendMessageDigest($delay, $type);

=head1 DESCRIPTION

sendMessageDigest() sends a digest of similarly-typed messages in the 
system queue.  Each message is marked according to its distribution frequency
(e.g. hourly, daily, weekly, monthly) and its type.  Messages with the same
type will have their message bodies grouped into a single digested mail.

=head1 PARAMETERS

Parameter 1 indicates the frequency of this digest run.

Parameter 2 is an optional parameter that specifies the message type for
this mailing.

Parameter 3 is an optional debug flag.

=head1 RETURN VALUE

Returns the number of messages sent in this digest run.

=cut

sub sendMessageDigest($;)
{
  my ($delay, $subject) = @_;

  # Find all messages of the same type and delay that haven't been sent.
  my $sth;
  my $knownType;
  my @markSentIds;
  my @handledIds;
  my @msg;

  log('notice', "Fetching messages of all types with delay $delay");

  $query = dbh()->prepare( SQL ) unless( $query );
  $query->execute( $delay, 1000 );

  my $currentPerson;
  my $currentDelivery;
  my $currentType;

  my $delayString = delayIdToString( $delay );
  my $renderedRef;
  my $summedBody = "";
  my @genNotiIds;
  my @toc;
  my $cnt = 1;

  while( my( $genNotiId, $notiId, $genNotiCreated, $subscriptId, $msgTypeId, $personId,
	     $delayId, $deliveryId ) = $query->fetchrow_array() ) {

    # set sensible start values if the current- values are undefined.
    $currentPerson   = $personId unless( $currentPerson );
    $currentDelivery = $deliveryId unless( $currentDelivery );
    $currentType     = $msgTypeId unless( $currentType );

    log( 'info', "Current Person $personId <=> $currentPerson" );
    log( 'info', "Current Delivery $deliveryId <=> $currentDelivery" );
    log( 'info', "Current Type $msgTypeId <=> $currentType" );

    if( $currentPerson   != $personId  ||
	$currentType     != $msgTypeId ||
	$currentDelivery != $deliveryId ) {
      # This means that the collected content needs to be sent because
      # the receiver changed or the receiver is the same but the delivery
      # is different or the message type has changed.
      my $s = $renderedRef->{subject};
      $renderedRef->{subject} = sprintf( "[digest %s] %d messages", $delayString, $cnt  );
      $renderedRef->{subject} .= ", eg. $s" if( $s );

      if( sendSummedMessage( $renderedRef, $summedBody, $currentDelivery ) ) {
	markSent( \@genNotiIds );
	@genNotiIds = ();
      }
      $summedBody = "";
      @toc = ();
      $cnt = 1;
    } else {
      # all parameters are still fine, we continue to collect gen_notification details
    }
    # query the parameter hash
    my $paramHash = getGeneratedNotificationParameters( $notiId );
    # render the message and get the digest text out.
    $renderedRef = renderMessage( $msgTypeId, $notiId, $subscriptId, $personId,
				  $delayId, $deliveryId, $paramHash );

    unless( $renderedRef->{body} ) {
      log( 'error', "Message without body is sad..." );
      next;
    }

    my $subject = sprintf("[%2d. %s] ", $cnt, $genNotiCreated );
    $subject .= ($renderedRef->{subject} || "no subject set");

    push @toc, $subject;

    # log('info', "Rendered Body: $renderedRef->{body}" );

    # get the <digest></digest> limited text out of the body.
    $summedBody .= ("\n" . $subject . "\n");
    if( $renderedRef->{body} =~ /<digest>(.+?)<\/digest>/gsi ) {
      # append the text part beween the digest tags to the summed body
      $summedBody .= $1;
    } else {
      # no digest sektion, append the whole text without signature
      my $sumBody = $renderedRef->{body};
      $sumBody =~ s/^-- \R.*$//sm;
      log('info', "Add to summed up body: $sumBody" );
      $summedBody .= $sumBody;
    }
    $currentPerson = $personId;
    $currentDelivery = $deliveryId;
    $currentType = $msgTypeId;
    push @genNotiIds, $genNotiId; # Needed to mark the notifications sent
    push @handledIds, $notiId;
    $cnt++;
  }

  # Send left overs.
  if( $renderedRef ) {
    my $cnt = @toc;
    my $s = $renderedRef->{subject};
    $renderedRef->{subject} = sprintf( "[digest %s] %d msgs", $delayString, $cnt  );
    $renderedRef->{subject} .= ", eg. $s" if( $s );

    log('info', "Sending left overs: " . Dumper $renderedRef );
    if( sendSummedMessage( $renderedRef, $summedBody, $currentDelivery, \@toc ) ) {
      markSent( \@genNotiIds );
    }
  }
  return \@handledIds;
}

sub sendSummedMessage( $$$$ )
{
  my ($msgRef, $summedBody, $deliveryId, $tocRef ) = @_;

  my $tocString = "Digest TOC:\n" . join( "\n", @$tocRef  ) . "\n";

  # Replace the body of the message with the collected body.
  my $bodyString = $msgRef->{body};

  if( $bodyString =~ /<digest>/ ) {
    $bodyString =~ s/<digest>.+?<\/digest>/$summedBody/gsi;
  } else {
    $bodyString = $summedBody;
  }
  $msgRef->{body} = $tocString . $bodyString;

  return deliverMessage( $deliveryId, $msgRef );
}




#
# This sub does the actual sending according to the method that is specified
# in the parameter delivery.
# The second parameter is a hash ref that contains the message details.
#
sub deliverMessage( $$ )
{
  my ($delivery, $msgRef) = @_;
  my $res = 0;

  my $deliveryString = deliveryIdToString( $delivery );

  unless( $deliveryString ) {
    log('warning', "Problem: Delivery <$delivery> seems to be unknown!" );
  } else {
    log( 'info', "Delivering this message: <$msgRef->{body}> with <$delivery> => $deliveryString" );

    # FIXME: Better detection of the delivery type
    if( $deliveryString =~ /mail/i ) {
      $res = sendMail( $msgRef );
    } elsif( $deliveryString =~ /jabber personal/i ) {
      # sendJabber( $msgRef );
      log( 'debug', "Unable to send Jabber at the moment!" );
      $res = 1;
    } elsif( $deliveryString =~ /RSS/i ) {
      $res = sendRSS( $msgRef ); # $res contains the id in the starship table
    } elsif( $deliveryString =~/HTTP/i ) {
      my $attribRef = deliveryAttribs( $delivery );
      my $url;
      $url = $attribRef->{url} if( exists( $attribRef->{url} ) );
      if( $url ) {
	$res = sendHTTP( $msgRef, $url );
      } else {
	log( 'error', "No URL defined for delivery-ID <$delivery>" );
	$res = 0;
      }
    } elsif( $Hermes::Config::DeliverTwitter && $deliveryString =~/Twitter/i ) {
      my $attribRef = deliveryAttribs( $delivery );
      $res = tweet( $attribRef, $msgRef->{body} );
    } else {
      log ( 'error', "No idea how to delivery message with delivery <$deliveryString>" );
    }
  }

  return $res;
}

#
# return the parameters with their values for one generated notification. 
# Digest messages have more of them.
sub getGeneratedNotificationParameters( $ ) 
{
  my ($notiId) = @_;

  # get all the information about the notification and its paramters
  my $sql = "SELECT n.sender, mt.msgtype, p.name, np.value FROM notifications n ";
  $sql .= "LEFT JOIN notification_parameters np ON( n.id=np.notification_id) ";
  $sql .= "LEFT JOIN parameters p ON (np.parameter_id=p.id) ";
  $sql .= "JOIN msg_types mt ON(mt.id=n.msg_type_id) WHERE n.id=?";

  my $sth = dbh()->prepare( $sql );
  $sth->execute( $notiId );
  my %paramHash;
  while( my( $s, $mt, $paraName, $paraValue) = $sth->fetchrow_array()) {

    if( $paraName ) {
      $paramHash{$paraName} = $paraValue || "";
    }
    $paramHash{_from} = $s unless $paramHash{_from};
    $paramHash{_type} = $mt unless $paramHash{_type};
  }

  $paramHash{_from} = $Hermes::Config::DefaultSender unless( $paramHash{_from} );
  return \%paramHash;
}

sub renderMessage( $$$$$$$ )
{
  my ($msgTypeId, $notiId, $subscriptId, $personId, $delayId, $deliveryId, $paramHash ) = @_;

  # for the moment we render all delivery- and delay types same way.

  my $type = $paramHash->{_type} || "unknown type";

  my $text;
  my $subject;

  # get an HTML::Template 
  my $tmpl = getTemplate( $type, $delayId, $deliveryId );
  if( $tmpl ) {
    # Fill the template, the expandMessageTemplateParams lives in Customize.pm
    $tmpl->param( expandMessageTemplateParams( $paramHash, $tmpl ) );
    $text = $tmpl->output;

    # extract the subject
    if( $text =~ /^\s*\@subject: ?(.+)$/im ) {
      $subject = $1;
      log( 'info', "Extracted subject <$subject> from template!" );
      $text =~ s/^\s*\@subject:.*$//im;
    }

    # remove a potential <digest> tag
    $text =~ s/<digest>//gsi;
    $text =~ s/<\/digest>//gsi;
    # log('info', "Template body: <$text>" );

  } else {
    log( 'warning', "No valid template found, using default" );
    $text = "Hermes received the notification <$type>\n\n";
    $subject = "Notification $type arrived!";
    if( keys %$paramHash ) {
      $text .= "These parameters were added to the notification:\n";
      foreach my $key( keys %$paramHash ) {
	$text .= "   $key = " . $paramHash->{$key} . "\n";
      }
    }
  }

  return { _notiId      => $notiId,
	   _subscriptId => $subscriptId,
	   _from        => $paramHash->{_from},
	   from         => $paramHash->{_from}, # for compat reasons.
	   to           => [$personId],
	   cc           => [],
	   bcc          => [],
	   type         => $type,
           _msgTypeId   => $msgTypeId,
	   replyto      => $paramHash->{_from},
	   subject      => $subject,
	   body         => $text,
	   _debug       => $Hermes::Config::Debug };

}


#
# FIXME: get template depending on user, delivery and delay
# from database.
#
sub getTemplate( $;$$ )
{
  my ($type, $delayId, $deliveryId ) = @_;

  my $text;
  my $filename = templateFileName( $type, $deliveryId );

  if( $filename && -r "$filename" ) {
    log( 'info', "template filename: <$filename>" );
    my $tmpl = HTML::Template->new( filename => "$filename",
				    die_on_bad_params => 0,
				    cache => 1 );

    return $tmpl;
  } else {
    log( 'debug', "Template not existing for type <$type>" );
  }

  return undef;
}

sub sendImmediateMessages(;$)
{
  my ($type) = @_;

  my $cnt = 0;
  $query = dbh()->prepare(SQL) unless( $query );
  $query->execute( SendNow(), 1000 );

  while( my( $genNotiId, $notiId, $genNotiCreated, $subscriptId, $msgTypeId,
	     $personId, $delayId, $deliveryId ) = $query->fetchrow_array() ) {

    my $renderedMsgRef;
    my $paramHash = getGeneratedNotificationParameters( $notiId );
    my $sender = $paramHash->{_from};
    my $type = $paramHash->{_type};

    # Check if this message should be kept in starship for reference 
    my $attribs = deliveryAttribs( $deliveryId );
    if( $attribs->{keepMsgInStarship} ) {
      my $starshipDelivery = $attribs->{keepMsgInStarship};
      $renderedMsgRef = renderMessage( $msgTypeId, $notiId, $subscriptId, $personId,
				       $delayId, $starshipDelivery, $paramHash );
      my $starship_id = deliverMessage( $starshipDelivery, $renderedMsgRef );
      log( 'info', "Starship-Message generated: $starship_id" );
      $paramHash->{_starshipId} = $starship_id;
    }

    $renderedMsgRef = renderMessage( $msgTypeId, $notiId, $subscriptId, $personId,
				     $delayId, $deliveryId, $paramHash );

    if( deliverMessage( $deliveryId, $renderedMsgRef ) ) {
      # Successfully sent!
      markSent( $genNotiId );
      $cnt ++;
      # log( 'info', "Successfully sent generated notification <$genNotiId>: ". 
      #  	   Dumper( $renderedMsgRef ) );
    } else {
      # FIXME: In case the second renderMessage went wrong, the starship-Message
      # needs to be wiped out.
    }
  }
  return $cnt;
}

#

log( 'info', "MessageSender Base Query: " . SQL );

1;

