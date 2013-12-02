package Net::CyanChat;

use strict;
use warnings;
use IO::Socket;
use IO::Select;

our $VERSION = '0.06';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {
		host      => 'cho.cyan.com', # Default CC Host
		port      => 1812,           # Default CC Port (1813=debugging)
		debug     => 0,              # Debug Mode
		proto     => 1,              # Use Protocol 1 (not 0)
		sock      => undef,          # Socket Object
		select    => undef,          # Select Object
		pinged    => 0,              # Last Ping Time
		refresh   => 60,             # Ping Rate = 60 Seconds
		nickname  => '',             # Our Nickname
		handlers  => {},             # Handlers
		connected => 0,              # Are We Connected?
		accepted  => 0,              # Logged in?
		who       => {},             # Who List
		ignored   => {},             # Ignored List
		nicks     => {},             # Nickname Lookup Table
		@_,
	};

	# Protocol support numbers: 0 and 1.
	if ($self->{proto} < 0 || $self->{proto} > 1) {
		die "Unsupported protocol version: must be 0 or 1!";
	}

	bless ($self,$class);
	return $self;
}

sub version {
	my ($self) = @_;
	return $VERSION;
}

sub debug {
	my ($self,$msg) = @_;

	return unless $self->{debug} == 1;
	print "Net::CyanChat::debug // $msg\n";
}

sub send {
	my ($self,$data) = @_;

	# Send the data.
	if (defined $self->{sock}) {
		$self->_event ('Packet', 'outgoing', $data);

		# Send true CrLf
		$self->{sock}->send ("$data\x0d\x0a") or do {
			# We've been disconnected!
			$self->{sock}->close();
			$self->{sock} = undef;
			$self->{select} = undef;
			$self->{connected} = 0;
			$self->{nick} = '';
			$self->{pinged} = 0;
			$self->{who} = {};
			$self->{nicks} = {};
			$self->_event ('Disconnected');
		};
	}
	else {
		warn "Could not send \"$data\" to CyanChat: connection not established!";
	}
}

sub setHandler {
	my ($self,$event,$code) = @_;

	# Set this handler.
	$self->{handlers}->{$event} = $code;
}

sub connect {
	my ($self) = @_;

	# Connect to CyanChat.
	$self->{sock} = new IO::Socket::INET (
		PeerAddr => $self->{host},
		PeerPort => $self->{port},
		Proto    => 'tcp',
	);

	# Error?
	if (!defined $self->{sock}) {
		$self->_event ('Error', "00|Connection Error", "Net::CyanChat Connection Error: $!");
	}

	# Create a select object.
	$self->{select} = IO::Select->new ($self->{sock});

	# Send that we're ready.
	$self->send ("40|$self->{proto}");
}

sub start {
	my ($self) = @_;

	while (1) {
		$self->do_one_loop or last;
	}
}

sub login {
	my ($self,$nick) = @_;

	if (length $nick > 0) {
		# Sign in.
		$self->send ("10|$nick");
		$self->{nickname} = $nick;
		return 1;
	}

	return 0;
}

sub logout {
	my ($self) = @_;

	return 0 unless length $self->{nickname} > 0;
	$self->{nickname} = '';
	$self->{accepted} = 0;
	$self->send ("15");
	return 1;
}

sub sendMessage {
	my ($self,$msg) = @_;

	# Send the message.
	return 0 unless length $msg > 0;
	$self->send ("30|^1$msg");
}

sub sendPrivate {
	my ($self,$to,$msg) = @_;

	return unless (length $to > 0 && length $msg > 0);
	# Get the user's full nick.
	my $nick = $self->{nicks}->{$to};

	# Send this user a message.
	$self->send ("20|$nick|^1$msg");
}

sub getBuddies {
	my ($self) = @_;

	# Return the buddylist.
	return $self->{who};
}

sub getFullName {
	my ($self,$who) = @_;

	# Return this user's full name.
	return $self->{full}->{$who} or 0;
}

sub getAddress {
	my ($self,$who) = @_;

	# Return this user's address.
	return $self->{who}->{$who} or 0;
}

sub protocol {
	my ($self) = @_;
	return $self->{proto};
}

sub nick {
	my ($self) = @_;

	return $self->{nickname};
}

sub ignore {
	my ($self,$who) = @_;

	# Ignore this user.
	return unless length $who > 0;
	$self->{ignored}->{$who} = 1;
	$self->send ("70|$who");
}
sub unignore {
	my ($self,$who) = @_;

	# Unignore this user.
	return unless length $who > 0;
	delete $self->{ignored}->{$who};
	$self->send ("70|$who");
}

sub authenticate {
	my ($self,$password) = @_;

	# Authenticate with a CC password.
	$self->send ("50|$password");
}

sub promote {
	my ($self,$user) = @_;

	# Promote this user to Special Guest.
	$self->send ("60|$user|4");
}

sub demote {
	my ($self,$user) = @_;

	# Demote this user.
	$self->send ("60|$user|0");
}

sub _event {
	my ($self,$event,@data) = @_;

	return unless exists $self->{handlers}->{$event};

	&{$self->{handlers}->{$event}} ($self,@data);
}

sub do_one_loop {
	my ($self) = @_;

	# Time to ping again?
	if ($self->{pinged} > 0) {
		# If connected...
		if ($self->{connected} == 1) {
			# If logged in...
			if ($self->{accepted} == 1) {
				# If refresh time has passed...
				if (time() - $self->{pinged} >= $self->{refresh}) {
					# To ping, send a private message to nobody.
					$self->send ("20||^1ping");
					$self->{pinged} = time();
				}
			}
		}
	}

	return unless defined $self->{select};

	# Loop with the server.
	my @ready = $self->{select}->can_read(.001);
	return unless(@ready);

	foreach my $socket (@ready) {
		my $resp;
		$self->{sock}->recv ($resp,2048,0);
		my @in = split(/\n/, $resp);

		# The server has sent us a message!
		foreach my $said (@in) {
			$said =~ s/\r//ig;
			my ($command,@args) = split(/\|/, $said);

			# The first message received?
			if ($self->{connected} == 0) {
				$self->{connected} = 1;
				$self->_event ('Connected');
				$self->{pinged} = time();
			}

			$self->_event ('Packet', 'incoming', $said);

			# Go through the commands.
			if ($command == 10) {
				# 10 = Name is invalid.
				$self->_event ('Error', 10, "Your name is invalid.");
			}
			elsif ($command == 11) {
				# 11 = Name accepted.
				$self->{accepted} = 1;
				$self->_event ('Name_Accepted');
			}
			elsif ($command == 21) {
				# 21 = Private Message
				my $type = 0;
				my ($level) = $args[0] =~ /^(\d)/;
				$type = $args[1] =~ /^\^(\d)/;
				$args[0] =~ s/^(\d)//ig;
				$args[1] =~ s/^\^(\d)//ig;

				# Get the sender's nick and address.
				my ($nick,$addr) = split(/\,/, $args[0], 2);

				# Skip ignored users.
				next if exists $self->{ignored}->{$nick};

				shift (@args);
				my $text = join ('|',@args);

				# Call the event.
				$self->_event ('Private', $nick, $level, $addr, $text);
			}
			elsif ($command == 31) {
				# 31 = Public Message.
				my $type = 1;
				my ($level) = $args[0] =~ /^(\d)/;
				($type) = $args[1] =~ /^\^(\d)/;
				$args[0] =~ s/^(\d)//i;
				$args[1] =~ s/^\^(\d)//i;

				# Get the sender's nick and address.
				my ($nick,$addr) = split(/\,/, $args[0], 2);

				# Skip ignored users.
				next if exists $self->{ignored}->{$nick};

				# Chop off spaces.
				$args[1] =~ s/^\s//ig;

				# Shift off data.
				shift (@args); # nickname
				my $text = join ('|',@args);

				# User has entered the room.
				if ($type == 2) {
					# Call the event.
					$self->_event ('Chat_Buddy_In', $nick, $level, $addr, $text);
				}
				elsif ($type == 3) {
					# Call the event.
					$self->_event ('Chat_Buddy_Out', $nick, $level, $addr, $text);
				}
				else {
					# Normal message.
					$self->_event ('Message', $nick, $level, $addr, $text);
				}
			}
			elsif ($command == 35) {
				# 35 = Who List Update.
				my %this = ();
				foreach my $user (@args) {
					my ($nick,$addr) = split(/\,/, $user, 2);
					my $fullNick = $nick;

					# Get data about this user.
					my ($level) = $nick =~ /^(\d)/;
					$nick =~ s/^(\d)//i;

					# User is online.
					$self->{who}->{$nick} = $addr;
					$this{$nick} = 1;

					# Call the event.
					$self->{nicks}->{$nick} = $fullNick;
					$self->_event ('Chat_Buddy_Here', $nick, $level, $addr);
				}

				# New event: WhoList = sends the entire Who List at once.
				$self->_event ('WhoList', @args);

				# See if anybody should be dropped.
				foreach my $who (keys %{$self->{who}}) {
					if (!exists $this{$who}) {
						# Buddy's gone.
						delete $self->{who}->{$who};
					}
				}
			}
			elsif ($command == 40) {
				# 40 = Server welcome message (the "pong" of 40 from the client).
				$self->_event ('Welcome', $args[0]);
			}
			elsif ($command == 70) {
				# 70 = Ignored/Unignored a user.
				my $user = $args[0];
				if (exists $self->{ignored}->{$user}) {
					delete $self->{ignored}->{$user};
					$self->_event ('Ignored', 0, $user);
				}
				else {
					$self->{ignored}->{$user} = 1;
					$self->_event ('Ignored', 1, $user);
				}
			}
			else {
				$self->debug ("Unknown event code from server: $command|"
					. join ('|', @args) );
			}
		}
	}

	return 1;
}

1;
__END__

=head1 NAME

Net::CyanChat - Perl interface for connecting to Cyan Worlds' chat room.

=head1 SYNOPSIS

  use Net::CyanChat;
  
  my $cyan = new Net::CyanChat (
        host    => 'cho.cyan.com', # default
        port    => 1812,           # main port--1813 is for testing
        proto   => 1,              # use protocol 1.0
        refresh => 60,             # ping rate (default)
  );

  # Set up handlers.
  $cyan->setHandler (foo => \&bar);

  # Connect
  $cyan->start();

=head1 DESCRIPTION

Net::CyanChat is a Perl module for object-oriented connections to Cyan Worlds, Inc.'s
chat room.

=head1 NOTE TO DEVELOPERS

Cyan Chat regulars really HATE bots! Recommended usage of this module is for developing
your own client, or a silent logging bot. Auto-Shorah (greeting users who enter the room)
is strongly advised against.

=head1 METHODS

=head2 new (ARGUMENTS)

Constructor for a new CyanChat object. Pass in any arguments you need. Some standard arguments
are: host (defaults to cho.cyan.com), port (defaults to 1812), proto (protocol version--0 or 1--defaults
to 1), debug, or refresh.

Returns a CyanChat object.

=head2 version

Returns the version number.

=head2 debug (MESSAGE)

Called by the module itself for debug messages.

=head2 send (DATA)

Send raw data to the CyanChat server.

=head2 setHandler (EVENT_CODE => CODEREF)

Set up a handler for the CyanChat connection. See below for a list of handlers.

=head2 connect

Connect to CyanChat's server.

=head2 start

Start a loop of do_one_loop's.

=head2 do_one_loop

Perform a single loop on the server.

=head2 login (NICK)

After receiving a "Connected" event from the server, it is okay to log in now. NICK
should be no more than 20 characters and cannot contain a pipe symbol "|".

This method can be called even after you have logged in once, for example if you want
to change your nickname without logging out and then back in.

=head2 logout

Log out of CyanChat. Must be logged in first.

=head2 sendMessage (MESSAGE)

Broadcast a message publicly to the chat room. Can only be called after you have logged
in through $cyan->login.

=head2 sendPrivate (TO, MESSAGE)

Send a private message to recipient TO. Must be logged in first.

=head2 getBuddies

Returns a hashref containing each buddy's username as the keys and their addresses as the values.

=head2 getFullName (NICK)

Returns the full name of passed in NICK. If NICK is not in the room, returns 0. FullName is the
name that CyanChat recognizes NICK by (including their auth code, i.e. "0username" for normal
users and "1username" for Cyan staff).

=head2 getAddress (NICK)

Returns the address to NICK. This is not their IP address; CyanChat encrypts their IP into this
address, and it is basicly a unique identifier for a connection. Multiple users logged on from the
same IP address will have the same chat address. Ignoring users will ignore them by address.

=head2 protocol

Returns the protocol version you are using. Will return 0 or 1.

=head2 ignore (USER), unignore (USER)

Ignore and unignore a username. When a user is ignored, the Message and Private events will not
be called when they send a message.

=head2 nick

Returns the currently signed in nickname of the CyanChat object.

=head1 ADVANCED METHODS

B<WARNING:> These methods are very dangerous to use if you don't know what you're doing.
Don't call authenticate() unless you know for sure what the CyanChat admin password is,
and don't call promote() or demote() unless you are already authenticated as a CyanChat
staff user.

Calling the authenticate() command with the wrong password will most likely get you
banned from CyanChat, and calling promote() or demote() without being an admin user
will probably have the same effect.

In other words, B<don't use these methods unless you know what you're doing!>

=head2 authenticate (PASSWORD)

Authenticate your connection as a Cyan Worlds staff member. Call this method before
entering the chat room.

=head2 promote (USER)

Promote USER to a Special Guest.

=head2 demote (USER)

Demote USER to a normal user level.

=head1 HANDLERS

=head2 Connected (CYANCHAT)

Called when a connection has been established, and the server recognizes your client's
presence. At this point, you can call CYANCHAT->login (NICK) to log into the chat room.

=head2 Disconnected (CYANCHAT)

Called when a disconnect has been detected.

=head2 Welcome (CYANCHAT, MESSAGE)

Called after the server recognizes your client (almost simultaneously to Connected).
MESSAGE are messages that the CyanChat server sends--mostly just includes a list of the
chat room's rules.

=head2 Message (CYANCHAT, NICK, LEVEL, ADDRESS, MESSAGE)

Called when a user sends a message publicly in chat. NICK is their nickname, LEVEL is their
auth level (0 = normal, 1 = Cyan employee, etc. - see below for full list). ADDRESS is their
chat address, and MESSAGE is their message.

=head2 Private (CYANCHAT, NICK, LEVEL, ADDRESS, MESSAGE)

Called when a user sends a private message to your client. All the arguments are the same
as the Message handler.

=head2 Ignored (CYANCHAT, IGNORE, NICK)

Called when a user has been ignored or unignored. IGNORE will be 1 (ignoring) or
0 (unignoring). NICK is their nickname.

=head2 Chat_Buddy_In (CYANCHAT, NICK, LEVEL, ADDRESS, MESSAGE)

Called when a buddy enters the chat room. NICK, LEVEL, and ADDRESS are the same as in the
Message and Private handlers. MESSAGE is their join message (i.e. "<links in from comcast.net age>")

=head2 Chat_Buddy_Out (CYANCHAT, NICK, LEVEL, ADDRESS, MESSAGE)

Called when a buddy exits. MESSAGE is their exit message (i.e. "<links safely back to their home Age>"
for normal log out, or "<mistakenly used an unsafe Linking Book without a maintainer's suit>" for
disconnected).

=head2 Chat_Buddy_Here (CYANCHAT, NICK, LEVEL, ADDRESS)

Called for each member currently in the room. Each time the Who List updates, this handler is called
for each buddy in the room.

=head2 WhoList (CYANCHAT, USERS)

This handler is called whenever a "35" (WhoList) event is received from the server. USERS is an array
of the raw user data the server sent. The array is full of elements of the format:

  #username,address

Where # is the auth level. Unlike Chat_Buddy_Here, your program needs to loop and parse out info
from each of the users.

=head2 Name_Accepted (CYANCHAT)

The CyanChat server has accepted your name.

=head2 Error (CYANCHAT, CODE, STRING)

Handles errors issued by CyanChat. CODE is the exact server code issued that caused the error.
STRING is either an English description or the exact text the server sent.

=head1 CYAN CHAT RULES

The CyanChat server strictly enforces these rules:

  Be respectful and sensitive to others (please, no platform wars).
  Keep it "G" rated (family viewing), both in language and content.
  And HAVE FUN!
  
  Termination of use can happen without warning!

=head1 CYAN CHAT AUTH LEVELS

Auth levels (received as LEVEL to most handlers, or prefixed onto a user's FullName) are as follows:

  0 is for regular chat user (should be in white)
  1 is for Cyan Worlds employee (should be in cyan)
  2 is for CyanChat Server message (should be in green)
  4 is for special guest (should be in gold)
  Any other number is probably a client error message (and is in red)

=head1 CHANGE LOG

Version 0.05

  - Fixed the end-of-line characters, it now sends a true CrLf.
  - Added the WhoList handler.
  - Added the authenticate(), promote(), and demote() methods.

Version 0.04

  - The enter/exit chat messages now go by the tag number (like it's supposed to),
    not by the contained text.
  - Messages can contain pipes in them and be read okay through the module.
  - Added a "ping" function. Apparently Cho will disconnect clients who don't do
    anything in 5 minutes. The "ping" function also helps detect disconnects!
  - The Disconnected handler has been added to detect disconnects.

Version 0.03

  - Bug fix: the $level received to most handlers used to be 1 (cyan staff) even
    though it should've been 0 (or any other number), so this has been fixed.

Version 0.01

  - Initial release.
  - Fully supports both protocols 0 and 1 of CyanChat.

=head1 SEE ALSO

Net::CyanChat::Server

CyanChat Protocol Documentation: http://cho.cyan.com/chat/programmers.html

=head1 AUTHOR

Cerone J. Kirsle <cjk "@" aichaos.com>

=head1 COPYRIGHT AND LICENSE

    Net::CyanChat - Perl interface to CyanChat.
    Copyright (C) 2005  Cerone J. Kirsle

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut
