#!/usr/bin/perl -w

# Perl CyanChat Client 3.0 - A complete rewrite from PCCC 1.x
# (C) 2006-07 Casey Kirsle

use strict;
use warnings;
use threads;
use threads::shared;

# Spawn a dedicated hyperlink-launching thread so we don't
# freeze up the MainWindow while a webpage loads.
our @HYPERLINKLIST : shared;
@HYPERLINKLIST = ();
our $HTTPBROWSER : shared;
our $linkthread = threads->create (sub {
	print "LinkerThread activated.\n";
	while (1) {
		select (undef,undef,undef,0.01);
		if (@HYPERLINKLIST) {
			my $next = shift @HYPERLINKLIST;

			print "Hyperlink: $next\n";

			if ($next eq "+shutdown") {
				# Shut things down.
				print "shutting down link thread\n";
				last;
			}

			system ("$HTTPBROWSER $next");
		}
	}
});

# Spawn a dedicated sound effect playing thread.
our @PLAYSOUNDS : shared;
@PLAYSOUNDS = ();
our $MEDIAPLAYER : shared;
$MEDIAPLAYER = undef;
our $mediathread = threads->create (sub {
	print "MediaThread activated.\n";

	# If this is on Windows, create the media player.
	my $win32mplayer = undef;
	if ($^O =~ /win(32|64)/i) {
		require Win32::MediaPlayer;
	}
	while (1) {
		select (undef,undef,undef,0.01);
		if (@PLAYSOUNDS) {
			my $next = shift @PLAYSOUNDS;

			print "MPlayer: $next\n";

			if ($next eq "+shutdown") {
				# Shut this thread down.
				print "shutting down media player\n";
				last;
			}

			# If the play command is undef, we might be on Windows.
			if (not defined $MEDIAPLAYER) {
				# To see for sure we're on Windows,
				# win32mplayer should have a value.
				$win32mplayer = new Win32::MediaPlayer;
				$win32mplayer->load ("./sfx/$next");
				$win32mplayer->play;
			}
			else {
				# Send this directly to the play command.
				system ("$MEDIAPLAYER ./sfx/$next");
			}
		}
	}
});

use lib "./lib";
use Net::CyanChat;
use Tk;
use Tk::ROText;
use Tk::NoteBook;
use Tk::LabFrame;
use Tk::Pane;
use Tk::Dialog;
use Tk::Balloon;
use Tk::BrowseEntry;
use Tk::HyperText;

our $MODIFIED = '21 June 2007';
our $VERSION = '3.0'; # Program Version
our $mw      = undef; # MainWindow Object
our %IMAGE   = ();    # Image Objects
our %menu    = ();    # Menu Items
our %config  = ();    # Configuration Data
our $homedir = '.';   # Home directory
our $FONT    = [];    # Reusable font definitions.
our $chat    = undef; # Chat Dialog Object
our $wholist = undef; # WhoList Object
our $adminlist = undef; # Cyan Staff & Guests WhoList
our $connected = 0;   # Not Connected
our $loggedin  = 0;   # Not Logged In
our $mutesfx   = 0;   # Temporarily mute all sounds
our $netcc   = undef; # Net::CyanChat object.
our %online  = ();    # Online Users List
our %ignore  = ();    # Ignore List
our %windows = ();    # Keep track of child windows.
our %private = ();    # Private text widgets.
our %pmsg    = ();    # Private message variables.
our %pfocus  = ();    # focus status on private msg windows
our @xhtml   = ();    # keeps xhtml version for logging
our $dbgtext = undef; # Debug messages text widget
our $tipper  = undef; # Tooltip balloon object
our %user    = (      # Personal user stuff.
	nick => '',
	msg  => '',
);
our $pOnlineList  = undef; # Preferences/Ignore - online users
our $pIgnoreList  = undef; # Preferences/Ignore - ignored users
our $hyperlink    = 0;     # Hyperlink ID incrementer
our $notification = [      # Window notification animation
	[ '>',   '<'   ],
	[ '>>',  '<<'  ],
	[ '>>>', '<<<' ],
	[ '',    ''    ],
	#[ '==>', '<==' ],
	#[ '===', '===' ],
	#[ '>==', '==<' ],
	#[ '=>=', '=<=' ],
	#[ '>=>', '<=<' ],
	#[ '=>=', '=<=' ],
];
our $winanim      = {};    # Window animation phases.
our $autologid    = 0;     # ID to stick with for autologging.
our $htmlhelp     = undef; # Help page HTML widget
our @helphistory  = ();    # Help page history
our $helpPage     = "index.html";
our $controlFrame = undef;
our $mainFrame    = undef;
our $rightFrame   = undef;
our $btnFrame    = undef;
our $whoFrame     = undef;
our $chatFrame    = undef;
our $msgboxFrame  = undef;
our $dialogFrame  = undef;

############################################
## Initialization                         ##
############################################
&init();

sub init {
	# Detect operating systems.
	&initOS();

	# Load configuration.
	&initConfig();

	# Draw the GUI.
	&initGUI();

	# Run the main loop.
	&loop();
}

sub initOS {
	# Find our operating system.
	my $os = $^O;

	print "Detecting your OS... $os\n";

	my $homename = '.pccc';
	if ($os =~ /win(32|64)/i) { # Microsoft Windows
		# HTTP Browser command = `start` by default.
		# MediaPlayer = undef (use Win32::MediaPlayer instead)
		$HTTPBROWSER = "start";
		$MEDIAPLAYER = undef;
		$homename    = "PCCC";
	}
	elsif ($os =~ /linux/i || $os =~ /unix/i) { # Linux, probably
		# HTTP Browser command = `htmlview` by default.
		# MediaPlayer = `play` by default.
		$HTTPBROWSER = "htmlview";
		$MEDIAPLAYER = "play";
		$homename    = ".pccc";
	}
	else {
		# Unknown OS (possibly Mac), use the same defaults as Linux.
		$HTTPBROWSER = "htmlview";
		$MEDIAPLAYER = "play";
		$homename    = ".pccc";
	}

	# Detect our home directory.
	my $home = $ENV{HOME} || $ENV{HOMEDIR} || $ENV{USERPROFILE} || '';
	$home =~ s~\\~/~g; # Fix Win32 paths.

	print "Detecting your home directory... $home\n";

	# If we have one...
	if (length $home) {
		# See if PCCC has a folder.
		if (!-d "$home/$homename") {
			# No. Make it.
			print "Making home directory $home/$homename\n";
			mkdir ("$home/$homename") or warn "Can't create config directory at "
				. "$home/$homename: $!";
		}

		# Now if it does...
		if (-d "$home/$homename") {
			# Set this as our home directory.
			print "Setting home directory to $home/$homename\n";
			$homedir = "$home/$homename";
		}
	}
}

sub initGUI {
	# Create a Tk MainWindow.
	our $mw = MainWindow->new (
		-title => "Perl CyanChat Client",
	);
	$mw->geometry ('640x480');
	$mw->optionAdd ('*tearOff','false');
	$mw->optionAdd ('*highlightThickness','0');
	$mw->protocol ('WM_DELETE_WINDOW', \&shutdown);

	# Load application icons.
	foreach (qw(worlds web balloon)) {
		$IMAGE{$_} = $mw->Photo (-file => "./$_\.gif", -format => 'GIF', -width => 32, -height => 32);
	}

	# Set the appicon.
	$mw->Icon (-image => $IMAGE{worlds});

	# Create the tooltip object.
	$tipper = $mw->Balloon (
		-balloonposition => 'mouse',
		-foreground      => '#000000',
		-background      => '#FFFFCC',
	);

	# Setup the notification animation states.
	$winanim->{__mainwindow__} = {
		title     => 'Perl CyanChat Client',
		focused   => -1,
		animating => 0,
		phase     => 0,
		proceed   => 0,
	};
	$mw->bind ('<FocusIn>', sub {
		$winanim->{__mainwindow__}->{focused} = 1;
		&animReset("__mainwindow__");
	});
	$mw->bind ('<FocusOut>', sub {
		$winanim->{__mainwindow__}->{focused} = 0;
	});

	# Create the debugging window (which shows all packets)
	$windows{__debug__} = $mw->Toplevel (
		-title => 'Debug Window',
	);
	$windows{__debug__}->geometry ('320x240');
	$windows{__debug__}->Icon (-image => $IMAGE{web});
	$windows{__debug__}->withdraw;
	$windows{__debug__}->protocol ('WM_DELETE_WINDOW', sub {
		return 0;
	});
	my $dbgBtm = $windows{__debug__}->Frame->pack (-fill => 'x', -side => 'bottom');
	my $dbgTop = $windows{__debug__}->Frame->pack (-fill => 'both', -expand => 1, -side => 'top');

	# Create the debug window's text viewer.
	$dbgtext = $dbgTop->Scrolled ('ROText',
		-scrollbars => 'e',
		-foreground => '#000000',
		-background => '#FFFFFF',
		-wrap       => 'word',
		-font       => [
			-family => 'Courier New',
			-size   => 10,
		],
	)->pack (-fill => 'both', -expand => 1);
	$dbgtext->tagConfigure ("server", -foreground => '#0000FF');
	$dbgtext->tagConfigure ("client", -foreground => '#FF0000');
	my $realtext = $dbgtext->Subwidget ('rotext');

	# Create the debug window buttons.
	$dbgBtm->Button (
		-text => 'Dismiss',
		-command => sub {
			$windows{__debug__}->withdraw;
		},
	)->grid (-column => 0, -row => 0, -padx => 10, -pady => 2);
	$dbgBtm->Button (
		-text => 'Clear',
		-command => sub {
			$dbgtext->delete ('0.0','end');
		},
	)->grid (-column => 1, -row => 0, -padx => 10, -pady => 2);

	# Create the menu bar.
	$menu{master} = $mw->Menu (
		-type => 'menubar',
	);
	$mw->configure (-menu => $menu{master});

	$menu{filemenu} = $menu{master}->cascade (
		-label => '~File',
		);

		$menu{filemenu}->command (-label => '~Save Transcript', -accelerator => 'Ctrl+S', -command => sub {
			#print "xhtml\n" . join ("\n",@xhtml);
			my $file = $mw->getSaveFile (
				-initialdir       => '.',
				-defaultextension => '.html',
				-filetypes        => [
					[ 'HTML Document', '*.html' ],
					[ 'Text Document', '*.txt' ],
					[ 'All Files',     '*.*'   ],
				],
			);

			return unless defined $file;

			if ($file =~ /\.txt$/i) {
				# Save as plain text.
				open (SAVE, ">$file");
				print SAVE $chat->get('1.0','end');
				close (SAVE);
			}
			else {
				# Save as HTML.
				&saveHTML ($file);
			}
		});

		$menu{filemenu}->command (-label => '~Clear Chat', -command => sub {
			# Do autologging first.
			&doAutolog();

			# Reset our autolog ID (start a new session)
			$autologid = 0;

			# Clear the chat and XHTML buffer.
			$chat->see ('0.0');
			$chat->delete ('0.0','end');
			@xhtml = ();
		});

		$menu{filemenu}->separator;

		$menu{forcequit} = $menu{filemenu}->command (-label => '~Force Quit', -accelerator => 'Ctrl+Alt+Q',
		-state => 'disabled', -command => sub {
			exit(0);
		});

		$menu{filemenu}->command (-label => '~Exit', -accelerator => 'Alt+F4', -command => sub {
			&shutdown();
		});

	$menu{editmenu} = $menu{master}->cascade (
		-label => '~Edit',
		);

		$menu{editmenu}->command (-label => '~Copy', -accelerator => 'Ctrl+C', -command => sub {
			$chat->Column_Copy_or_Cut (0);
		});

		$menu{editmenu}->command (-label => '~Find...', -accelerator => 'Ctrl+F', -command => sub {
			$chat->findandreplacepopup (1);
		});

		$menu{editmenu}->command (-label => '~Select All', -accelerator => 'Ctrl+A', -command => sub {
			$chat->selectAll();
		});

		$menu{editmenu}->command (-label => '~Unselect All', -command => sub {
			$chat->unselectAll();
		});

	$menu{chatmenu} = $menu{master}->cascade (
		-label => '~Chat',
		);

		$menu{connect} = $menu{chatmenu}->command (-label => '~Connect', -command => sub {
			&connect();
		});
		$menu{disconnect} = $menu{chatmenu}->command (-label => '~Disconnect', -state => 'disabled', -command => sub {
			&disconnect();
		});

		$menu{details} = $menu{chatmenu}->command (-label => 'Connection Detail~s', -state => 'disabled', -command => sub {
			if (exists $windows{__condetails__}) {
				$windows{__condetails__}->focusForce;
			}
			else {
				$windows{__condetails__} = $mw->Toplevel (
					-title => 'Connection Details',
				);
				$windows{__condetails__}->Icon (-image => $IMAGE{web});
				$windows{__condetails__}->bind ('<Destroy>', sub {
					delete $windows{__condetails__};
				});

				my $serv = '(Custom)';
				my $port = '(Custom)';

				if ($config{chathost} eq 'cho.cyan.com') {
					$serv = '(Cyan Worlds)';
				}
				if ($config{chatport} == 1812) {
					$port = '(Default)';
				}
				elsif ($config{chatport} == 1813) {
					$port = '(Testing)';
				}

				$windows{__condetails__}->Label (
					-text => 'Chat Server:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 0, -sticky => 'e');

				$windows{__condetails__}->Label (
					-textvariable => \$config{chathost},
					-font         => $FONT,
				)->grid (-column => 1, -row => 0, -sticky => 'w');

				$windows{__condetails__}->Label (
					-textvariable => \$serv,
					-font         => $FONT,
				)->grid (-column => 2, -row => 0, -sticky => 'w');

				$windows{__condetails__}->Label (
					-text => 'Chat Port:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 1, -sticky => 'e');

				$windows{__condetails__}->Label (
					-textvariable => \$config{chatport},
					-font         => $FONT,
				)->grid (-column => 1, -row => 1, -sticky => 'w');

				$windows{__condetails__}->Label (
					-textvariable => \$port,
					-font         => $FONT,
				)->grid (-column => 2, -row => 1, -sticky => 'w');

				$windows{__condetails__}->Label (
					-text => 'Status:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 2, -sticky => 'e');

				$windows{__condetails__}->Label (
					-text => 'Connected.',
					-font => $FONT,
				)->grid (-column => 1, -row => 2, -sticky => 'w');

				$windows{__condetails__}->Button (
					-text => 'Close',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
					-command => sub {
						$windows{__condetails__}->destroy;
					},
				)->grid (-column => 0, -columnspan => 3, -row => 3, -sticky => 'n');

				$windows{__condetails__}->focusForce;
			}
		});

		$menu{chatmenu}->separator;

		$menu{chatmenu}->command (-label => '~Open Console', -command => sub {
			$windows{__debug__}->deiconify;
			$dbgtext->see ('end');
		});

		$menu{rawmenu} = $menu{chatmenu}->command (-label => '~Send Raw Command', -state => 'disabled', -command => sub {
			my $win = $mw->Toplevel (
				-title => 'Send Raw Command',
			);
			$win->geometry ('400x100');
			$win->Icon (-image => $IMAGE{web});

			$win->Label (
				-text => "Use this tool to send a raw command directly to CyanChat.\n"
					. "Only use this if you know what you're doing. If you get banned\n"
					. "from CyanChat for sending a bad command, it's not my fault.",
			)->pack;
			my $packet = '';
			$win->Entry (
				-textvariable => \$packet,
			)->pack (-fill => 'x');

			my $frame = $win->Frame->pack (-fill => 'x');

			$frame->Button (
				-text => 'Spawn Debug Window',
				-command => sub {
					$windows{__debug__}->deiconify;
					$dbgtext->see ('end');
				},
			)->pack (-side => 'left');

			$frame->Button (
				-text => 'Send Command',
				-command => sub {
					$netcc->send ($packet);
					$packet = '';
				},
			)->pack (-side => 'left');

			$frame->Button (
				-text => 'Close',
				-command => sub {
					$win->destroy;
				},
			)->pack (-side => 'left');
		});

		$menu{chatmenu}->separator;

		$menu{chatmenu}->command (-label => '~Preferences', -accelerator => 'F3', -command => sub {
			&prefs();
		});

		$menu{chatmenu}->separator;

		$menu{chatmenu}->checkbutton (
			-label    => '~Mute Sounds',
			-variable => \$mutesfx,
			-onvalue  => 1,
			-offvalue => 0,
		);

	$menu{helpmenu} = $menu{master}->cascade (
		-label => '~Help',
		);

		$menu{helpmenu}->command (-label => '~About PCCC', -command => sub {
			&help("about.html");
		});

		$menu{helpmenu}->command (-label => '~Contents', -accelerator => 'F1', -command => sub {
			&help();
		});

		$menu{helpmenu}->separator;

		$menu{linkmenu} = $menu{helpmenu}->cascade (
			-label => '~Links',
			);

			$menu{linkmenu}->command (-label => '~PCCC Homepage', -command => sub {
				push (@HYPERLINKLIST, "http://www.cuvou.com/?module=pccc");
			});

			$menu{linkmenu}->command (-label => '~SourceForge Project Page', -command => sub {
				push (@HYPERLINKLIST, "http://www.sourceforge.net/projects/perlccc");
			});

			$menu{linkmenu}->command (-label => '~Cuvou.com', -command => sub {
				push (@HYPERLINKLIST, "http://www.cuvou.com/");
			});

			$menu{linkmenu}->separator;

			$menu{linkmenu}->command (-label => 'CyanChat ~Homepage', -command => sub {
				push (@HYPERLINKLIST, "http://cho.cyan.com/chat/");
			});

			$menu{linkmenu}->command (-label => 'CC P~rogrammers', -command => sub {
				push (@HYPERLINKLIST, "http://cho.cyan.com/chat/programmers.html");
			});

			$menu{linkmenu}->command (-label => 'Cyan ~Worlds', -command => sub {
				push (@HYPERLINKLIST, "http://www.cyanworlds.com/");
			});

			$menu{linkmenu}->separator;

			$menu{linkmenu}->command (-label => 'CC ~Quote Database', -command => sub {
				push (@HYPERLINKLIST, "http://cyanchat.dnijazzclub.com/");
			});

	# Create the layout Frames.
	$controlFrame = $mw->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'top', -fill => 'x');
	$mainFrame = $mw->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'top', -fill => 'both', -expand => 1);
	$rightFrame = $mainFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'right', -fill => 'y');
	$btnFrame = $rightFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'bottom', -fill => 'x');
	$whoFrame = $rightFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'bottom', -fill => 'both', -expand => 1);

	$chatFrame = $mainFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'right', -fill => 'both', -expand => 1);

	my $msgSide = $config{orientation} || 'top';
	$msgSide = 'top' unless $msgSide eq 'bottom';

	if ($msgSide eq 'top') {
		$msgboxFrame = $chatFrame->Frame (
			-background => $config{windowbg},
		)->pack (-side => 'top', -fill => 'x');
		$dialogFrame = $chatFrame->Frame (
			-background => $config{windowbg},
		)->pack (-side => 'top', -fill => 'both', -expand => 1);
	}
	else {
		$msgboxFrame = $chatFrame->Frame (
			-background => $config{windowbg},
		)->pack (-side => 'bottom', -fill => 'x');
		$dialogFrame = $chatFrame->Frame (
			-background => $config{windowbg},
		)->pack (-side => 'bottom', -fill => 'both', -expand => 1);
	}

	##########################
	# Control Frame          #
	##########################

	$controlFrame->Label (
		-image  => $IMAGE{worlds},
		-border => 2,
		-relief => 'raised',
	)->pack (-side => 'left', -pady => 0, -padx => 0);

	$menu{loginlabel} = $controlFrame->Label (
		-text       => "Name:",
		-foreground => $config{windowfg},
		-background => $config{windowbg},
		-font       => $FONT,
	)->pack (-side => 'left', -padx => 2);

	$menu{logintext} = $controlFrame->Entry (
		-textvariable => \$user{nick},
		-foreground   => $config{inputfg},
		-background   => $config{inputbg},
		-disabledforeground => $config{windowfg},
		-disabledbackground => $config{windowbg},
		-width        => 20,
		-font         => $FONT,
		-highlightthickness => 0,
	)->pack (-side => 'left', -padx => 2);

	$menu{loginbttn} = $controlFrame->Button (
		-text       => 'Join Chat',
		-foreground => $config{buttonfg},
		-background => $config{buttonbg},
		-activeforeground   => $config{buttonfg},
		-activebackground   => $config{buttonbg},
		-disabledforeground => $config{disabledfg},
		-state      => 'disabled',
		-font       => $FONT,
		-command    => \&enterChat,
		-highlightthickness => 0,
	)->pack (-side => 'left', -padx => 2);

	$menu{constatus} = $controlFrame->Label (
		-text       => 'Not connected to CyanChat.',
		-foreground => $config{clientcolor},
		-background => $config{windowbg},
		-font       => $FONT,
	)->pack (-side => 'left', -padx => 2);

	##########################
	# Who Frame              #
	##########################

	my $autobttnFrame = $btnFrame->Frame (
		-background => $config{windowbg},
	)->pack (-fill => 'x');

	$menu{autobttn} = $autobttnFrame->Checkbutton (
		-text => 'Autoscroll',
		-foreground => $config{buttonfg},
		-background => $config{buttonbg},
		-activeforeground => $config{buttonfg},
		-activebackground => $config{buttonbg},
		-font       => $FONT,
		-variable   => \$config{autoscroll},
		-highlightthickness => 0,
	)->pack (-side => 'left', -fill => 'x', -padx => 2, -pady => 1);

	my $tsFrame = $btnFrame->Frame (
		-background => $config{windowbg},
	)->pack (-fill => 'x');

	$menu{timebttn} = $tsFrame->Checkbutton (
		-text => 'Time stamps',
		-foreground => $config{buttonfg},
		-background => $config{buttonbg},
		-activeforeground => $config{buttonfg},
		-activebackground => $config{buttonbg},
		-font       => $FONT,
		-variable   => \$config{timestamps},
		-highlightthickness => 0,
		-command    => sub {
			my @opts = (
				-foreground => $config{background},
				-elide      => 1,
			);
			if ($config{timestamps} == 1) {
				@opts = (
					-foreground => $config{servercolor},
					-elide      => 0,
				);
			}
			$chat->tagConfigure ("timestamp",
				-font => [
					@{$FONT},
					-size => 8,
				],
				@opts,
			);
		},
	)->pack (-side => 'left', -fill => 'x', -padx => 2, -pady => 1);

	$menu{privatebttn} = $btnFrame->Button (
		-text => 'Send Private',
		-foreground => $config{buttonfg},
		-background => $config{buttonbg},
		-activeforeground   => $config{buttonfg},
		-activebackground   => $config{buttonbg},
		-disabledforeground => $config{disabledfg},
		-state      => 'disabled',
		-font       => $FONT,
		-command    => \&sendPrivate,
		-highlightthickness => 0,
	)->pack (-fill => 'x', -padx => 2, -pady => 1);

	$menu{ignorebttn} = $btnFrame->Button (
		-text => 'Ignore',
		-foreground => $config{buttonfg},
		-background => $config{buttonbg},
		-activeforeground   => $config{buttonfg},
		-activebackground   => $config{buttonbg},
		-disabledforeground => $config{disabledfg},
		-state      => 'disabled',
		-font       => $FONT,
		-command    => \&ignoreUser,
		-highlightthickness => 0,
	)->pack (-fill => 'x', -padx => 2, -pady => 1);

	my $admnFrame = $whoFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'bottom', -fill => 'x');

	$admnFrame->Label (
		-text       => 'Cyan & Guests:',
		-foreground => $config{windowfg},
		-background => $config{windowbg},
		-font       => $FONT,
	)->pack (-side => 'top', -anchor => 'w');

	$adminlist = $admnFrame->Scrolled ('Listbox',
		-foreground => $config{foreground},
		-background => $config{whobg},
		-scrollbars => 'osoe',
		-height     => 5,
		-font       => $FONT,
		-selectforeground   => '#000000',
		-selectbackground   => '#CCCCFF',
		-highlightthickness => 0,
	)->pack (-side => 'top', -fill => 'x');

	my $wholistFrame = $whoFrame->Frame (
		-background => $config{windowbg},
	)->pack (-side => 'bottom', -fill => 'both', -expand => 1);

	$menu{wholabel} = $wholistFrame->Label (
		-text       => 'Who is online:',
		-foreground => $config{windowfg},
		-background => $config{windowbg},
		-font       => $FONT,
	)->pack (-side => 'top', -anchor => 'w');

	$wholist = $wholistFrame->Scrolled ('Listbox',
		-foreground => $config{foreground},
		-background => $config{whobg},
		-scrollbars => 'osoe',
		-font       => $FONT,
		-selectforeground   => '#000000',
		-selectbackground   => '#CCCCFF',
		-highlightthickness => 0,
	)->pack (-side => 'top', -fill => 'both', -expand => 1);

	# Bind the Who List for right-clicking and middle-clicking.
	$wholist->bind ('<ButtonRelease-3>', \&wholistRightClick);
	$wholist->bind ('<Button-2>', \&wholistMiddleClick);
	$wholist->bind ('<Double-1>', \&sendIM);

	# Bind the special Who List too.
	$adminlist->bind ('<ButtonRelease-3>', [\&wholistRightClick,"admin"]);
	$adminlist->bind ('<Button-2>', \&wholistMiddleClick);
	$adminlist->bind ('<Double-1>', \&adminlistSendIM);

	$menu{msgbox} = $msgboxFrame->Entry (
		-textvariable => \$user{msg},
		-foreground   => $config{inputfg},
		-background   => $config{inputbg},
		-disabledforeground => $config{windowfg},
		-disabledbackground => $config{windowbg},
		-state        => 'disabled',
		-width        => 20,
		-font         => $FONT,
		-highlightthickness => 0,
	)->pack (-fill => 'x', -expand => 1);

	$chat = $dialogFrame->Scrolled ('ROText',
		-foreground => $config{foreground},
		-background => $config{background},
		-scrollbars => 'ose',
		-wrap       => 'word',
		-font       => $FONT,
		-highlightthickness => 0,
	)->pack (-fill => 'both', -expand => 1);

	# Bind all the tags.
	&bindChatTags();

	# Add some introductory messages.
	&sendLine (from => 'ChatClient', color => 'client', message => "Welcome to Perl CyanChat Client v. $VERSION!");

	##########################
	# Key Bindings           #
	##########################

	$mw->bind ('<Return>', \&bind_return);
	$mw->bind ('<Control-s>', sub {
		my $file = $mw->getSaveFile (
			-initialdir       => '.',
			-defaultextension => '.html',
			-filetypes        => [
				[ 'HTML Document', '*.html' ],
				[ 'Text Document', '*.txt' ],
				[ 'All Files',     '*.*'   ],
			],
		);

		return unless defined $file;

		if ($file =~ /\.txt$/i) {
			# Save as plain text.
			open (SAVE, ">$file");
			print SAVE $chat->get('1.0','end');
			close (SAVE);
		}
		else {
			# Save as HTML.
			&saveHTML ($file);
		}
	});
	$mw->bind ('<Alt-F4>', \&shutdown);
	$mw->bind ('<Control-f>', sub {
		$chat->findandreplacepopup (1);
	});
	$mw->bind ('<Control-a>', sub {
		$chat->selectAll;
	});
	$mw->bind ('<F1>', sub {
		&help();
	});
	$mw->bind ('<F3>', \&prefs);
	$mw->bind ('<Control-Alt-q>', sub { exit(0); });

	if ($config{autoconnect} == 1) {
		&connect();
	}
}

sub initConfig {
	my $skip = shift || 'no';

	# Specify the default settings in case there is no config file present.
	%config = (
		chathost     => 'cho.cyan.com', # ChatHost     = the CyanChat server hostname
		chatport     => 1812,           # ChatPort     = the CyanChat server port
		autoconnect  => 0,              # AutoConnect  = automatically connect on startup
		reconnect    => 1,              # ReConnect    = automatically reconnect on disconnect
		dialogfont   => 'Arial',        # DialogFont   = the font for the CyanChat dialog widgets
		reversechat  => 1,              # ReverseChat  = new messages on top (default)
		fontsize     => 10,             # FontSize     = font size
		autoscroll   => 1,              # AutoScroll   = automatically scroll on new messages
		nickname     => '',             # Nickname     = a default value for nick
		autojoin     => 0,              # AutoJoin     = automatically join the chat (if length Nickname)
		blockserver  => 0,              # BlockServer  = ignore ChatServer's messages
		ignoreback   => 1,              # IgnoreBack   = perform mutual ignore
		loudignore   => 1,              # LoudIgnore   = show messages when people ignore you
		sendignore   => 1,              # SendIgnore   = send the ignore command when ignoring
		autoact      => 1,              # AutoAct      = *..* messages are /me equivalents
		loudtypo     => 1,              # LoudTypo     = show notifications about typo's
		browser      => $HTTPBROWSER,   # Browser      = console command to link URLs
		orientation  => 'top',          # Orientation  = input box's position
		timestamps   => 0,              # TimeStamps   = show timestamps on messages
		imwindows    => 1,              # IMWindows    = show "IM" style windows for private messages
		stickyignore => 0,              # StickyIgnore = remember who I ignored
		notifyanimate => 1,             # NotifyAnimate = animate the window titles for notifications
		autologging  => 0,              # Autologging  = automatically log chat dialog
		mediaplayer  => "play",         # MediaPlayer  = MPlayer program (not applicable to Windows)
		playsounds   => 1,              # PlaySounds   = global sound playing switch
		playjoin     => 1,              # PlayJoin     = play sound when user joins
		playleave    => 1,              # PlayLeave    = play sound when user leaves
		playpublic   => 0,              # PlayPublic   = play sound on public message
		playprivate  => 1,              # PlayPrivate  = play sound on private message
		joinsound    => "link.wav",     # JoinSound    = sound effect when user enters the room
		leavesound   => "link.wav",     # LeaveSound   = sound effect when user leaves the room
		publicsound  => "ding.wav",     # PublicSound  = sound effect to play on public message
		privatesound => "message.wav",  # PrivateSound = sound effect to play on private message
		windowbg     => '#000000',      # WindowBG     = the BG color for MainWindow
		windowfg     => '#CCCCCC',      # WindowFG     = the FG color for MainWindow
		buttonbg     => '#000000',      # ButtonBG     = the BG color for buttons
		buttonfg     => '#CCCCCC',      # ButtonFG     = the FG color for buttons
		whobg        => '#000000',      # WhoBG        = the BG color for Who List
		background   => '#000000',      # Background   = the BG color for CyanChat
		foreground   => '#CCCCCC',      # Foreground   = the FG color
		inputbg      => '#FFFFFF',      # InputBG      = text box input BG
		inputfg      => '#000000',      # InputFG      = text box input FG
		disabledfg   => '#999999',      # DisabledFG   = foreground for disabled buttons
		linkcolor    => '#0099FF',      # LinkColor    = hyperlink colors
		usercolor    => '#FFFFFF',      # UserColor    = white
		echocolor    => '#FFFFFF',      # EchoColor    = white
		admincolor   => '#00FFFF',      # AdminColor   = cyan
		guestcolor   => '#FF9900',      # GuestColor   = yellow
		servercolor  => '#00FF00',      # ServerColor  = lime
		clientcolor  => '#FF0000',      # ClientColor  = red
		privatecolor => '#FF99FF',      # PrivateColor = pink (magenta on black = ugly)
		actioncolor  => '#FFFF00',      # ActionColor  = orange
	);

	if ($skip ne 'skip' && -f "$homedir/config.txt") {
		print "Reading configuration from $homedir/config.txt\n";
		open (CFG, "$homedir/config.txt");
		my @cfg = <CFG>;
		close (CFG);
		chomp @cfg;

		foreach my $line (@cfg) {
			next unless defined $line;
			next if $line eq '';
			next unless length $line > 0;

			my ($label,$data) = split(/\s+/, $line, 2);
			$label = lc($label);

			$config{$label} = $data;
		}
	}

	$FONT       = [
		-family => $config{dialogfont},
		-size   => $config{fontsize},
	];

	if ($skip ne 'cancel') {
		$user{nick} = $config{nickname};
	}

	$HTTPBROWSER = $config{browser};

	# Reload our saved ignore lists?
	if (-f "$homedir/ignore.txt") {
		print "Reading saved ignore list from $homedir/ignore.txt\n";
		open (READ, "$homedir/ignore.txt");
		my @read = <READ>;
		close (READ);
		chomp @read;

		foreach my $line (@read) {
			print "$line\n";
			$ignore{$line} = 1;
		}
	}
}

############################################
## Main Methods                           ##
############################################

sub bindChatTags {
	foreach (qw(user admin guest server client private action echo)) {
		my $var = $_ . "color";
		$chat->tagConfigure ($_, -foreground => $config{$var});
	}

	my @opts = (
		-foreground => $config{background},
		-elide      => 1,
	);
	if ($config{timestamps} == 1) {
		@opts = (
			-foreground => $config{servercolor},
			-elide      => 0,
		);
	}
	$chat->tagConfigure ("timestamp",
		-font => [
			@{$FONT},
			-size => 8,
		],
		@opts,
	);

	$chat->configure (-foreground => $config{foreground}, -background => $config{background});

	# (Re)color the window.
	$controlFrame->configure (-background => $config{windowbg});
	$mainFrame->configure (-background => $config{windowbg});
	$rightFrame->configure (-background => $config{windowbg});
	$btnFrame->configure (-background => $config{windowbg});
	$whoFrame->configure (-background => $config{windowbg});
	$chatFrame->configure (-background => $config{windowbg});

	$menu{loginlabel}->configure (-foreground => $config{windowfg}, -background => $config{windowbg});
	$menu{logintext}->configure (-disabledforeground => $config{windowfg}, -disabledbackground => $config{windowbg},
		-foreground => $config{inputfg}, -background => $config{inputbg});
	$menu{loginbttn}->configure (-foreground => $config{buttonfg}, -background => $config{buttonbg},
		-activeforeground => $config{buttonfg}, -activebackground => $config{buttonbg}, -disabledforeground => $config{disabledfg});
	$menu{constatus}->configure (-background => $config{windowbg});
	$menu{privatebttn}->configure (-foreground => $config{buttonfg}, -background => $config{buttonbg},
		-activeforeground => $config{buttonfg}, -activebackground => $config{buttonbg}, -disabledforeground => $config{disabledfg});
	$menu{ignorebttn}->configure (-foreground => $config{buttonfg}, -background => $config{buttonbg},
		-activeforeground => $config{buttonfg}, -activebackground => $config{buttonbg}, -disabledforeground => $config{disabledfg});
	$menu{wholabel}->configure (-foreground => $config{windowfg}, -background => $config{windowbg});
	$wholist->configure (-foreground => $config{foreground}, -background => $config{whobg});
	$menu{msgbox}->configure (-disabledforeground => $config{windowfg}, -disabledbackground => $config{windowbg},
		-foreground => $config{inputfg}, -background => $config{inputbg});

	# Refresh the Who List.
	&updateWhoList;

	# Update the connection status label.
	if ($connected) {
		$menu{constatus}->configure (-foreground => $config{servercolor});
	}
	else {
		$menu{constatus}->configure (-foreground => $config{clientcolor});
	}
}

sub sendMsgLine {
	my ($where,$str,$deftag) = @_; # where = '0.0' or 'end'
	$deftag = '' unless defined $deftag;

	#print "sendMsgLine ($where,$str)\n";

	# This is a universal subroutine for sending the "message" part of a user's message
	# to a chat or private message window. This allows the hyperlinking function to be
	# easy and universal.

	# Isolate the hyperlinks.
	$str =~ s~(\s*)((http|https|ftp)://[^\s]+)(\s*)~$1<pccchttp::httphyperlink>$2<pccchttp::httpendhyperlink>$4~ig;

	# Split the message at hyperlinks.
	my @parts = split(/<pccchttp::/, $str);

	if ($where eq '0.0') {
		$chat->insert ($where,"\n");
		@parts = reverse(@parts);
	}

	# Go through each one.
	foreach my $part (@parts) {
		#print "part: $part\n";

		# If this part is to a hyperlink...
		if ($part =~ /^httphyperlink>/) {
			# Cut off the PCCC Hyperlink tag.
			$part =~ s/^httphyperlink>//i;

			#print ":: Found a hyperlink: $part\n";

			# Create a unique hyperlink tag.
			my $tag = "hyperlink" . $hyperlink++;
			$chat->tagConfigure ($tag, -underline => 1, -foreground => $config{linkcolor});

			# Bind this tag to an anonymous function.
			$chat->tagBind ($tag, "<Button-1>", [
				sub {
					my $link = $_[1];
					#print "link clicked: $link\n";
					push (@HYPERLINKLIST, $link);
				},
				$part,
			]);
			$chat->tagBind ($tag,"<Any-Enter>", sub {
				$chat->configure (-cursor => 'hand2');
			});
			$chat->tagBind ($tag,"<Any-Leave>", sub {
				$chat->configure (-cursor => 'xterm');
			});

			# Insert this.
			$chat->insert ($where,$part,$tag);
		}
		else {
			$part =~ s/^httpendhyperlink>//i;
			$chat->insert ($where,$part,$deftag);
		}
	}

	if ($where eq 'end') {
		$chat->insert ($where,"\n");
	}
}

sub sendLine {
	my (%data) = @_;

	if ($data{from} eq $user{nick}) {
		$data{color} = 'echo';
	}

	my $stamp = &timestamp;

	push (@xhtml, "<div class=\"message\">"
		. "<span class=\"timestamp\">$stamp</span> <span class=\"$data{color}\">[$data{from}]</span> "
		. &htmlEscape($data{message}) . "</div>");

	#print "sendLine (" . each(%data) . ")\n";

	if ($config{reversechat} == 1) {
		&sendMsgLine ('0.0',$data{message});
		$chat->insert ('0.0', "[$data{from}] ",$data{color});
		$chat->insert ('0.0', "$stamp ","timestamp");
		if ($config{autoscroll} == 1) {
			$chat->see ('0.0');
		}
	}
	else {
		$chat->insert ('end', "$stamp ","timestamp");
		$chat->insert ('end', "[$data{from}] ",$data{color});
		&sendMsgLine ('end',$data{message});
		if ($config{autoscroll} == 1) {
			$chat->see ('end');
		}
	}

	if ($config{notifyanimate} == 1 && $winanim->{__mainwindow__}->{focused} == 0) {
		$winanim->{__mainwindow__}->{animating} = 1;
	}
	&doAutolog();
}
sub sendBlankLine {
	push (@xhtml, "<div class=\"message\">&nbsp;</div>");

	if ($config{reversechat} == 1) {
		$chat->insert ('0.0', "\n");
		if ($config{autoscroll} == 1) {
			$chat->see ('0.0');
		}
	}
	else {
		$chat->insert ('end',"\n");
		if ($config{autoscroll} == 1) {
			$chat->see ('end');
		}
	}

	if ($config{notifyanimate} == 1 && $winanim->{__mainwindow__}->{focused} == 0) {
		$winanim->{__mainwindow__}->{animating} = 1;
	}
	&doAutolog();
}
sub sendMoveLine {
	my (%data) = @_;

	if ($data{from} eq $user{nick}) {
		$data{color} = 'echo';
	}

	my $escape = &htmlEscape($data{message});
	my $stamp = &timestamp;

	push (@xhtml, "<div class=\"message\"><span class=\"timestamp\">$stamp</span> "
		. "<span class=\"server\">$data{prefix}</span>"
		. "<span class=\"$data{color}\">[$data{from}]</span> $escape"
		. "<span class=\"server\">$data{suffix}</span></div>");

	if ($config{reversechat} == 1) {
		$chat->insert ('0.0', "$data{suffix}\n",'server');
		$chat->insert ('0.0', "$data{message}");
		$chat->insert ('0.0', "[$data{from}] ",$data{color});
		$chat->insert ('0.0', "$data{prefix}",'server');
		$chat->insert ('0.0', "$stamp ",'timestamp');
		if ($config{autoscroll} == 1) {
			$chat->see ('0.0');
		}
	}
	else {
		$chat->insert ('end', "$stamp ",'timestamp');
		$chat->insert ('end', "$data{prefix}",'server');
		$chat->insert ('end', "[$data{from}] ",$data{color});
		$chat->insert ('end', "$data{message}");
		$chat->insert ('end', "$data{suffix}\n",'server');
		if ($config{autoscroll} == 1) {
			$chat->see ('end');
		}
	}

	if ($config{notifyanimate} == 1 && $winanim->{__mainwindow__}->{focused} == 0) {
		$winanim->{__mainwindow__}->{animating} = 1;
	}
	&doAutolog();
}
sub sendActionLine {
	my (%data) = @_;

	my ($typo) = (exists $data{typo} && $data{typo} eq "true") ? "true" : "false";

	if ($data{from} eq $user{nick}) {
		$data{color} = 'echo';
	}

	my $stamp = &timestamp;

	push (@xhtml, "<div class=\"message\"><span class=\"timestamp\">$stamp</span> "
		. "<span class=\"$data{color}\">[$data{from}]</span> "
		. "<span class=\"action\">"
		. &htmlEscape($data{message}) . "</span></div>");

	if ($config{reversechat} == 1) {
		if ($typo eq "true") {
			&sendMsgLine ('0.0',$data{message},'action');
			$chat->insert ('0.0', "[$data{from}] ",$data{color});
		}
		else {
			&sendMsgLine ('0.0',"$data{message} **",'action');
			$chat->insert ('0.0', "$data{from} ",$data{color});
			$chat->insert ('0.0', "** ",'action');
		}
		$chat->insert ('0.0', "$stamp ",'timestamp');
		if ($config{autoscroll} == 1) {
			$chat->see ('0.0');
		}
	}
	else {
		$chat->insert ('end', "$stamp ",'timestamp');
		if ($typo eq "true") {
			$chat->insert ('end', "[$data{from}] ",$data{color});
			&sendMsgLine ('end',$data{message},'action');
		}
		else {
			$chat->insert ('end', "** ",'action');
			$chat->insert ('end', "$data{from} ",$data{color});
			&sendMsgLine ('end',"$data{message} **",'action');
		}
		if ($config{autoscroll} == 1) {
			$chat->see ('end');
		}
	}

	if ($config{notifyanimate} == 1 && $winanim->{__mainwindow__}->{focused} == 0) {
		$winanim->{__mainwindow__}->{animating} = 1;
	}
	&doAutolog();
}
sub sendPrivLine {
	my (%data) = @_;

	my $stamp = &timestamp;

	if ($data{from} eq $user{nick}) {
		$data{color} = 'echo';
	}

	my $popupImWindow = 0;
	if ($config{imwindows} == 1) {
		$popupImWindow = 1;
	}
	elsif (exists $data{popup} && $data{popup} == 1) {
		$popupImWindow = 1;
	}

	if ($popupImWindow == 1 && not exists $windows{$data{from}}) {
		# Set us up for window animating.
		$winanim->{$data{from}} = {
			title     => "$data{from} | CyanChat",
			focused   => -1,
			animating => 0,
			phase     => 0,
			proceed   => 0,
		};

		$windows{$data{from}} = $mw->Toplevel (
			-title => "$data{from} | CyanChat",
		);
		$windows{$data{from}}->geometry ('320x240');
		$windows{$data{from}}->Icon (-image => $IMAGE{balloon});
		$windows{$data{from}}->bind ('<Destroy>', [ sub {
			my $id = $_[1];
			delete $winanim->{$id};
			delete $windows{$id};
		}, $data{from}]);
		$windows{$data{from}}->bind ('<FocusIn>', [ sub {
			$windows{$data{from}}->configure (-title => "$_[1] | CyanChat");
			$pfocus{$_[1]} = 1;
			$winanim->{$_[1]}->{focused} = 1;
			&animReset($_[1]);
		}, $data{from}]);
		$windows{$data{from}}->bind ('<FocusOut>', [ sub {
			$pfocus{$_[1]} = 0;
			$winanim->{$_[1]}->{focused} = 0;
		}, $data{from}]);

		my $Frame = $windows{$data{from}}->Frame (
			-background => $config{background},
		)->pack (-side => 'top', -fill => 'both', -expand => 1);

		my $inputFrame = $Frame->Frame (
			-background => $config{background},
		)->pack (-side => 'top', -fill => 'x');
		my $dlgFrame = $Frame->Frame (
			-background => $config{background},
		)->pack (-side => 'top', -fill => 'both', -expand => 1);

		$inputFrame->Entry (
			-textvariable => \$pmsg{$data{from}},
			-foreground   => $config{inputfg},
			-background   => $config{inputbg},
			-font         => $FONT,
			-highlightthickness => 0,
		)->pack (-fill => 'x', -expand => 1)->focusForce;

		$private{$data{from}} = $dlgFrame->Scrolled ('ROText',
			-foreground => $config{foreground},
			-background => $config{background},
			-scrollbars => 'ose',
			-wrap       => 'word',
			-font       => $FONT,
			-highlightthickness => 0,
		)->pack (-fill => 'both', -expand => 1);

		$private{$data{from}}->tagConfigure ('user', -foreground => $config{usercolor});
		$private{$data{from}}->tagConfigure ('private', -foreground => $config{privatecolor});

		if (defined $data{default}) {
			$private{$data{from}}->insert ('end', "[$user{nick}] ",'user');
			$private{$data{from}}->insert ('end', "$data{default}\n");
			$private{$data{from}}->see ('end');
		}

		$windows{$data{from}}->focusForce;
		$pfocus{$data{from}} = 1;

		$windows{$data{from}}->bind ('<Return>', [ sub {
			my $user = $_[1];

			if (length $pmsg{$user}) {
				$private{$data{from}}->insert ('end', "[$user{nick}] ",'user');
				$private{$data{from}}->insert ('end', "$pmsg{$user}\n");
				$private{$data{from}}->see ('end');
				&sendLine (from => 'ChatClient', color => 'client', message => "Private message sent to: [$user] $pmsg{$user}");
				$netcc->sendPrivate ($user,$pmsg{$user});
				$pmsg{$user} = '';
			}
		}, $data{from} ]);
	}

	return unless length $data{message};

	if (exists $windows{$data{from}}) {
		$private{$data{from}}->insert ('end', "[$data{from}] ",'private');
		$private{$data{from}}->insert ('end', "$data{message}\n");

		if ($pfocus{$data{from}} == 0) {
			$windows{$data{from}}->configure (-title => ">>> $data{from} | CyanChat <<<");
		}

		$private{$data{from}}->see ('end');

		if ($config{notifyanimate} == 1 && $winanim->{$data{from}}->{focused} == 0) {
			$winanim->{$data{from}}->{animating} = 1;
		}
	}

	push (@xhtml, "<div class=\"message\"><span class=\"timestamp\">$stamp</span> "
		. "<span class=\"private\">Private message from</span> "
		. "<span class=\"$data{color}\">[$data{from}]</span> "
		. &htmlEscape($data{message}) . "</div>");

	if ($config{reversechat} == 1) {
		&sendMsgLine ('0.0',$data{message});
		$chat->insert ('0.0', "[$data{from}] ",$data{color});
		$chat->insert ('0.0', "Private message from ",'private');
		$chat->insert ('0.0', "$stamp ",'timestamp');
		if ($config{autoscroll} == 1) {
			$chat->see ('0.0');
		}
	}
	else {
		$chat->insert ('end', "$stamp ",'timestamp');
		$chat->insert ('end', "Private message from ",'private');
		$chat->insert ('end', "[$data{from}] ",$data{color});
		&sendMsgLine ('end',$data{message});
		if ($config{autoscroll} == 1) {
			$chat->see ('end');
		}
	}

	if ($config{notifyanimate} == 1 && $winanim->{__mainwindow__}->{focused} == 0) {
		$winanim->{__mainwindow__}->{animating} = 1;
	}
	&doAutolog();
}

sub connect {
	# Create a new Net::CyanChat object.
	$netcc = new Net::CyanChat (
		host  => $config{chathost},
		port  => $config{chatport},
		proto => 1,
		debug => 1,
	);

	# Set handlers.
	$netcc->setHandler (Connected       => \&on_connected);
	$netcc->setHandler (Disconnected    => \&on_disconnected);
	$netcc->setHandler (Welcome         => \&on_welcome);
	$netcc->setHandler (Message         => \&on_message);
	$netcc->setHandler (Private         => \&on_private);
	$netcc->setHandler (Chat_Buddy_In   => \&on_enter);
	$netcc->setHandler (Chat_Buddy_Out  => \&on_exit);
	#$netcc->setHandler (Chat_Buddy_Here => \&on_here);
	$netcc->setHandler (WhoList         => \&on_wholist);
	$netcc->setHandler (Name_Accepted   => \&on_name_accepted);
	$netcc->setHandler (Ignored         => \&on_ignored);
	$netcc->setHandler (Packet          => \&on_packet);
	$netcc->setHandler (Error           => \&on_error);

	&sendBlankLine();
	&sendLine (from => 'ChatClient', color => 'client', message => "Connecting to CyanChat...");

	$menu{constatus}->configure (
		-text       => 'Connecting...',
		-foreground => $config{clientcolor},
	);

	# Connect.
	$connected = 1;
	$netcc->connect();
}

sub disconnect {
	if ($loggedin) {
		&exitChat;
	}

	$netcc->{sock}->close();
	$netcc = undef;

	$connected = 0;
	$menu{constatus}->configure (
		-text       => 'Not connected.',
		-foreground => $config{clientcolor},
	);
	$menu{connect}->configure (-state => 'normal');
	$menu{disconnect}->configure (-state => 'disabled');
	$menu{details}->configure (-state => 'disabled');
	$menu{rawmenu}->configure (-state => 'disabled');
	$menu{loginbttn}->configure (-state => 'disabled');
	$menu{privatebttn}->configure (-state => 'disabled');
	$menu{ignorebttn}->configure (-state => 'disabled');
	$menu{logintext}->focusForce;

	# Clear the who list.
	$wholist->delete (0,'end');
	%online = ();
	%ignore = ();
}

sub enterChat {
	my $nick = $user{nick};

	if (length $nick) {
		if (length $nick > 20 || $nick =~ /\|/) {
			&sendLine (from => 'ChatClient', color => 'client', message => "Your nickname must be less than 20 characters "
				. "and cannot contain a pipe symbol (\"|\")");
		}
		else {
			# It should be good.
			$netcc->login ($nick);
		}
	}
	else {
		&sendLine (from => 'ChatClient', color => 'client', message => "Please enter a nickname before joining chat.");
	}
}

sub exitChat {
	$netcc->logout;

	$loggedin = 0;

	$menu{loginbttn}->configure (
		-text => 'Join Chat',
		-command => \&enterChat,
	);
	$menu{logintext}->configure (
		-state => 'normal',
	);
	$menu{msgbox}->configure (
		-state => 'disabled',
	);
	$menu{logintext}->focusForce;
}

sub sendMessage {
	my $msg = $user{msg} || '';

	# Filter line breaks from the message (they might've accidentally been pasted in).
	$msg =~ s/\x0a//g;
	$msg =~ s/\x0d//g;

	if (length $msg > 0 && $loggedin == 1) {
		# Run commands.
		if ($msg =~ /^\/(?:whisper|w|msg) (.+?)$/i) {
			my ($to,$what) = split(/\s+/, $1, 2);

			if (length $to && length $what) {
				if (not exists $private{$to}) {
					&sendPrivLine (from => $to, color => 'server', message => '', default => $what);
				}
				&sendLine (from => 'ChatClient', color => 'client', message => "Private message sent to: [$to] $what");
				$netcc->sendPrivate ($to,$what);
			}
			else {
				&sendLine (from => 'ChatClient', color => 'client', message => "Usage: /whisper <username> <message>");
			}

			$user{msg} = '';
		}
		else {
			$netcc->sendMessage ($msg);
			$user{msg} = '';
		}
	}
}

sub sendPrivate {
	# Get the selected user.
	my $index = ($wholist->curselection)[0];

	if (length $index) {
		my $user = $wholist->get ($index);
		my $msg = $user{msg} || '';

		if (length $msg > 0 && length $user > 0 && $loggedin == 1) {
			if (not exists $private{$user}) {
				&sendPrivLine (from => $user, color => 'server', message => '', default => $user{msg});
			}

			&sendLine (from => 'ChatClient', color => 'client', message => "Private message sent to: [$user] $msg");
			$netcc->sendPrivate ($user,$msg);
			$user{msg} = '';
		}
		else {
			&sendLine (from => 'ChatClient', color => 'client', message => "Select a user from the Who List and write a message.");
		}
	}
	else {
		&sendLine (from => 'ChatClient', color => 'client', message => "Select a user from the Who List and write a message.");
	}
}

sub sendIM {
	# Get the selected user.
	my $name = $_[1] || undef;

	my $user = undef;

	if (not defined $name) {
		my $index = ($wholist->curselection)[0];
		$user = $wholist->get ($index);
	}
	else {
		$user = $name;
	}

	my $msg = $user{msg} || '';

	if (exists $windows{$user}) {
		$windows{$user}->focusForce;
	}
	else {
		&sendPrivLine (from => $user, color => 'server', message => '', popup => 1);
	}
}

sub adminlistSendIM {
	# Get the selected user.
	my $index = ($adminlist->curselection)[0];

	if (length $index) {
		my $user = $adminlist->get ($index);
		my $msg = $user{msg} || '';

		if (exists $windows{$user}) {
			$windows{$user}->focusForce;
		}
		else {
			&sendPrivLine (from => $user, color => 'server', message => '', popup => 1);
		}
	}
}

sub ignoreUser {
	my $name = $_[1] || undef;

	#print "ignoreUser(@_)\n";

	my $user = undef;
	if (not defined $name) {
		#print "name not defined\n";
		my $index = ($wholist->curselection)[0];

		if (length $index) {
			$user = $wholist->get ($index);
		}
	}
	else {
		$user = $name;
	}

	return unless defined $user;

	if (exists $ignore{$user}) {
		if ($config{sendignore} == 1) {
			$netcc->unignore ($user);
		}
		delete $ignore{$user};
		&sendLine (from => 'ChatClient', color => 'client', message => "No longer ignoring messages from $user.");
	}
	else {
		if ($config{sendignore} == 1) {
			$netcc->ignore ($user);
		}
		$ignore{$user} = 1;
		&sendLine (from => 'ChatClient', color => 'client', message => "Now ingoring messages from $user.");
	}
}

sub wholistRightClick {
	my $listbox = shift;
	my $admin = shift || '';

	# Get the cursor position.
	my $cursor = $Tk::event->y;

	# Find out what name we're over.
	my $name = $listbox->get ($listbox->nearest ($cursor));

	# Select this user.
	$listbox->selectionClear (0,'end');
	$listbox->selectionSet ($listbox->nearest($cursor));

	# Return if something went wrong.
	return unless length $name;

	# Get their address.
	my ($level,$addr) = split(/\;/, $online{$name}, 2);

	&sendLine (
		from    => 'ChatClient',
		color   => 'client',
		message => "$name is chatting from the address $addr",
	);
}

sub wholistMiddleClick {
	my $listbox = shift;

	# Get the cursor position.
	my $cursor = $Tk::event->y;

	# Find out what name we're over.
	my $name = $listbox->get ($listbox->nearest ($cursor));

	# Select this user.
	$listbox->selectionClear (0,'end');
	$listbox->selectionSet ($listbox->nearest($cursor));

	# Return if something went wrong.
	return unless length $name;

	# Add their name to our message.
	$user{msg} .= $name;
}

sub getColor {
	my $code = shift;

	if ($code == 0) {
		return 'user';
	}
	elsif ($code == 1) {
		return 'admin';
	}
	elsif ($code == 2) {
		return 'server';
	}
	elsif ($code == 4) {
		return 'guest';
	}

	return 'client';
}

sub savePrefs {
	# Save preferences in a logical order.
	my @order = (
		'ChatHost',
		'ChatPort',
		'AutoConnect',
		'ReConnect',
		'DialogFont',
		'ReverseChat',
		'FontSize',
		'AutoScroll',
		'Nickname',
		'AutoJoin',
		'BlockServer',
		'IgnoreBack',
		'LoudIgnore',
		'SendIgnore',
		'AutoAct',
		'LoudTypo',
		'Browser',
		'Orientation',
		'TimeStamps',
		'IMWindows',
		'StickyIgnore',
		'NotifyAnimate',
		'Autologging',
		'MediaPlayer',
		'PlaySounds',
		'PlayJoin',
		'PlayLeave',
		'PlayPublic',
		'PlayPrivate',
		'JoinSound',
		'LeaveSound',
		'PublicSound',
		'PrivateSound',
		'WindowBG',
		'WindowFG',
		'ButtonBG',
		'ButtonFG',
		'WhoBG',
		'Background',
		'Foreground',
		'InputBG',
		'InputFG',
		'DisabledFG',
		'LinkColor',
		'UserColor',
		'EchoColor',
		'AdminColor',
		'GuestColor',
		'ServerColor',
		'ClientColor',
		'PrivateColor',
		'ActionColor',
	);

	$HTTPBROWSER = $config{browser};

	my @lines = ();
	#print "lines = @lines\n";
	foreach (@order) {
		my $var = lc($_);

		$_ .= " " until length $_ == 15;

		push (@lines, $_ . $config{$var});
	}

	open (SAVE, ">$homedir/config.txt");
	print SAVE join ("\n",@lines);
	close (SAVE);
}

sub shutdown {
	$menu{forcequit}->configure (-state => 'normal');

	# Save our ignore list.
	if ($config{stickyignore} == 1) {
		#print "Save ignore list:\n";
		print Dumper(%ignore);
		my @save = ();
		foreach my $key (keys %ignore) {
			push (@save,"$key");
		}
		#print join ("\n",@save);

		open (IGNORE, ">$homedir/ignore.txt");
		print IGNORE join ("\n",@save);
		close (IGNORE);
	}
	else {
		# We no longer want to save ignores, so delete the file.
		if (-f "$homedir/ignore.txt") {
			#print "Delete the ignore list\n";
			unlink ("$homedir/ignore.txt");
		}
	}

	# If we're connected...
	if ($connected) {
		my $dialog = $mw->Dialog (
			-title          => 'Exit PCCC?',
			-text           => "You are currently connected to CyanChat. Disconnect and exit?",
			-buttons        => [ 'Yes', 'No' ],
			-default_button => 'Yes',
		);
		$dialog->Icon (-image => $IMAGE{worlds});

		my $choice = $dialog->Show;
		if ($choice =~ /yes/i) {
			&disconnect();
		}
		else {
			return;
		}
	}

	$mw->destroy;

	# Send the link thread a signal to start wrapping things up.
	push (@HYPERLINKLIST, "+shutdown");
	push (@PLAYSOUNDS, "+shutdown");

	# Join the child threads.
	$linkthread->join;
	$mediathread->join;

	exit(0);
}

sub loop {
	$| = 1;
	while (1) {
		select (undef,undef,undef,0.001);
		$mw->update;

		if ($connected) {
			$netcc->do_one_loop;
		}

		# Animate all windows.
		foreach my $winName (keys %{$winanim}) {
			if ($winanim->{$winName}->{animating} == 1) {
				&animStep ($winName);
			}
		}
	}
}

sub animReset {
	my $name = shift;

	if ($name eq '__mainwindow__') {
		#print "Reset animation for MW\n";
		$mw->configure (-title => $winanim->{__mainwindow__}->{title});
		$winanim->{__mainwindow__} = {
			title     => $winanim->{__mainwindow__}->{title},
			focused   => $winanim->{__mainwindow__}->{focused},
			phase     => 0,
			animating => 0,
			proceed   => 0,
		};
	}
	else {
		#print "Reset animation for $name\n";
		$windows{$name}->configure (-title => $winanim->{$name}->{title});
		$winanim->{$name} = {
			title     => $winanim->{$name}->{title},
			focused   => $winanim->{$name}->{focused},
			phase     => 0,
			animating => 0,
			proceed   => 0,
		};
	}
}

sub animStep {
	my $name = shift;

	if ($name eq '__mainwindow__') {
		if ($winanim->{$name}->{focused} == 1) {
			&animReset('__mainwindow__');
			return;
		}

		if ($winanim->{__mainwindow__}->{proceed} <= 0) {
			# Up the phase.
			$winanim->{__mainwindow__}->{phase}++;
			if ($winanim->{__mainwindow__}->{phase} >= scalar @{$notification}) {
				$winanim->{__mainwindow__}->{phase} = 0;
			}

			my $suffix = $notification->[ $winanim->{__mainwindow__}->{phase} ];
			my ($left,$right) = @{$suffix};

			#print "step: $left$winanim->{__mainwindow__}->{title}$right\n";

			$mw->configure (-title => $left . $winanim->{__mainwindow__}->{title} . $right);
			$winanim->{__mainwindow__}->{proceed} = 200;
		}
		$winanim->{__mainwindow__}->{proceed}--;
	}
	else {
		if ($winanim->{$name}->{focused} == 1) {
			&animReset($name);
			return;
		}

		if ($winanim->{$name}->{proceed} <= 0) {
			# Up the phase.
			$winanim->{$name}->{phase}++;
			if ($winanim->{$name}->{phase} >= scalar @{$notification}) {
				$winanim->{$name}->{phase} = 0;
			}

			my $suffix = $notification->[ $winanim->{$name}->{phase} ];
			my ($left,$right) = @{$suffix};

			#print "step: $left$winanim->{$name}->{title}$right\n";

			$windows{$name}->configure (-title => $left . $winanim->{$name}->{title} . $right);
			$winanim->{$name}->{proceed} = 200;
		}
		$winanim->{$name}->{proceed}--;
	}
}

############################################
## Keyboard Bindings and Events           ##
############################################

sub bind_return {
	if ($connected) {
		if (not $loggedin) {
			&enterChat;
		}
		else {
			&sendMessage;
		}
	}
}

############################################
## Handlers                               ##
############################################

sub on_connected {
	my $cc = shift;

	$menu{constatus}->configure (
		-text       => 'Connected to CyanChat.',
		-foreground => $config{servercolor},
	);
	$menu{connect}->configure (-state => 'disabled');
	$menu{disconnect}->configure (-state => 'normal');
	$menu{details}->configure (-state => 'normal');
	$menu{rawmenu}->configure (-state => 'normal');
	$menu{loginbttn}->configure (-state => 'normal');
	$menu{privatebttn}->configure (-state => 'normal');
	$menu{ignorebttn}->configure (-state => 'normal');
	$menu{logintext}->focusForce;

	&sendLine (from => 'ChatClient', color => 'client', message => "Connection established!");

	# If auto-login...
	if ($config{autojoin} == 1) {
		if (length $config{nickname}) {
			$cc->login ($config{nickname});
		}
	}
}

sub on_disconnected {
	my $cc = shift;

	$connected = 0;
	$menu{constatus}->configure (
		-text       => 'Not connected.',
		-foreground => $config{clientcolor},
	);
	$menu{connect}->configure (-state => 'normal');
	$menu{disconnect}->configure (-state => 'disabled');
	$menu{details}->configure (-state => 'disabled');
	$menu{rawmenu}->configure (-state => 'disabled');
	$menu{loginbttn}->configure (-state => 'disabled');
	$menu{privatebttn}->configure (-state => 'disabled');
	$menu{ignorebttn}->configure (-state => 'disabled');

	$loggedin = 0;
	$menu{loginbttn}->configure (
		-text => 'Join Chat',
		-command => \&enterChat,
	);
	$menu{logintext}->configure (
		-state => 'normal',
	);
	$menu{msgbox}->configure (
		-state => 'disabled',
	);
	$menu{logintext}->focusForce;

	&sendLine (from => 'ChatClient', color => 'client', message => "You have been disconnected from the server.");

	# Clear the Who List.
	$wholist->delete (0,'end');

	if ($config{reconnect}) {
		&connect();
	}
}

sub on_packet {
	my ($cc,$source,$packet) = @_;

	if ($source eq "incoming") {
		$dbgtext->insert ('end',"$packet\n","server");
	}
	else {
		$dbgtext->insert ('end',"$packet\n","client");
	}
}

sub on_welcome {
	my ($cc,$msg) = @_;

	$msg =~ s/^\d//g;
	$msg =~ s/\r//g;

	&sendLine (from => 'ChatServer', color => 'server', message => $msg);
}

sub on_message {
	my ($cc,$nick,$level,$addr,$msg) = @_;

	$msg =~ s/\r//g;

	if ($level == 2) {
		# Ignoring server messages?
		if ($config{blockserver} == 1) {
			return;
		}
	}

	if (not exists $ignore{$nick}) {
		&playSound ("public");
		if ($msg =~ /^\/me (.+?)$/i) {
			&sendActionLine (from => $nick, color => &getColor($level), message => $1);
		}
		elsif ($config{autoact} == 1 && $msg =~ /^\*(.+?)\*$/i) {
			&sendActionLine (from => $nick, color => &getColor($level), message => $1);
		}
		elsif ($config{loudtypo} == 1 && $msg =~ /^\*([^\*]+?)$/i) {
			&sendActionLine (from => $nick, color => &getColor($level), message => $msg, typo => 'true');
		}
		else {
			&sendLine (time => time(), from => $nick, color => &getColor($level), message => $msg);
		}
	}
}

sub on_private {
	my ($cc,$nick,$level,$addr,$msg) = @_;

	$msg =~ s/\r//g;

	if ($level == 2) {
		# Ignoring server messages?
		if ($config{blockserver} == 1) {
			return;
		}
	}

	if (not exists $ignore{$nick}) {
		&playSound ("private");
		&sendPrivLine (from => $nick, color => &getColor($level), message => $msg);
	}
}

sub on_enter {
	my ($cc,$nick,$level,$addr,$msg) = @_;

	&playSound ("join");

	$msg =~ s/\r//g;
	&sendMoveLine (from => $nick, color => &getColor($level), message => $msg, prefix => '\\\\\\\\\\', suffix => '/////');

	$online{$nick} = join (";",$level,$addr);
	&updateWhoList;

	# Play a SFX.
	#push (@PLAYSOUNDS, "email.wav");
}

sub on_exit {
	my ($cc,$nick,$level,$addr,$msg) = @_;

	&playSound ("leave");

	$msg =~ s/\r//g;
	&sendMoveLine (from => $nick, color => &getColor($level), message => $msg, prefix => '/////', suffix => '\\\\\\\\\\');

	delete $online{$nick};
	&updateWhoList;
}

sub on_here {
	my ($cc,$nick,$level,$addr) = @_;

	my $user = $nick;

	if (exists $online{$user}) {
		# Ignore.
	}
	else {
		$online{$nick} = join (";",$level,$addr);
	}

	&updateWhoList;
}

sub on_wholist {
	my ($cc,@users) = @_;

	#print "wholist: @users\n";

	my %comp = ();
	foreach my $name (@users) {
		my ($nick,$addr) = split(/\,/, $name, 2);
		my $user = $nick;
		my ($level) = $user =~ /^(\d)/;
		$user =~ s/^\d//;

		#print "check newuser $user\n";

		if (exists $online{$user}) {
			# They're already here.
			#print "\tuser already here\n";
		}
		else {
			# They're new.
			#print "\tthis is a new user!\n";
		}

		$online{$user} = join (";",$level,$addr);

		$comp{$user} = 1;
	}

	# Look for missing users.
	foreach my $nln (keys %online) {
		#print "marked online user: $nln\n";
		if (not exists $comp{$nln}) {
			#print "not exists in comp\n";
			# Delete them.
			delete $online{$nln};
		}
	}

	&updateWhoList();
}

sub updateWhoList {
	$wholist->delete (0,'end');
	$adminlist->delete (0,'end');

	foreach my $user (keys %online) {
		my ($level,$addr) = split(/\;/, $online{$user}, 2);
		my $color = &getColor($level);
		my $type  = join ('',$color,'color');

		#print "Update wholists ($user; $level; $addr; $color; $type)\n";

		if ($color eq 'admin' || $color eq 'guest') {
			$adminlist->insert ('end',$user);
			$adminlist->itemconfigure ('end', -foreground => $config{$type});
		}
		else {
			$wholist->insert ('end',$user);
			$wholist->itemconfigure ('end', -foreground => $config{$type});
		}
	}
}

sub on_name_accepted {
	my ($cc) = @_;

	$loggedin = 1;

	# Our name was accepted!
	$menu{loginbttn}->configure (
		-text => 'Exit Chat',
		-command => \&exitChat,
	);
	$menu{logintext}->configure (
		-state => 'disabled',
	);
	$menu{msgbox}->configure (
		-state => 'normal',
	);

	$menu{msgbox}->focusForce;
}

sub on_ignored {
	my ($cc,$ignore,$user) = @_;

	# Showing ignore notifications?
	if ($config{loudignore} == 1) {
		&sendLine (time => time(), from => 'ChatClient', color => 'client', message => "$user has ignored you.");
	}

	# Doing mutual ignores?
	if ($config{ignoreback} == 1) {
		$cc->ignore ($user);
	}
}

sub on_error {
	my ($cc,$code,$string) = @_;

	&sendLine (from => 'ChatServer', color => 'server', message => $string);
}

sub htmlEscape {
	my $str = shift;

	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	$str =~ s/\"/&quot;/g;
	$str =~ s/\'/&apos;/g;

	return $str;
}

sub timestamp {
	# Generate the time stamp.
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
	$hour = "0" . $hour until length $hour == 2;
	$min  = "0" . $min  until length $min  == 2;

	return "$hour:$min";
}

sub doAutolog {
	# Is autologging enabled?
	if ($config{autologging} == 1) {
		# Make log directories, if necessary.
		my ($sec,$min,$hour,$day,$mon,$year,$wday,$yday,$isdst) = localtime(time());
		$mon++;
		$mon = "0" . $mon until length $mon == 2;
		$day = "0" . $day until length $day == 2;
		$year += 1900;
		my $dir = join ("-",$year,$mon,$day);

		if (!-d "$homedir/logs") {
			print "mkdir $homedir/logs\n";
			mkdir ("$homedir/logs") or warn "can't mkdir $homedir/logs: $!";
		}
		if (!-d "$homedir/logs/$dir") {
			print "mkdir $homedir/logs/$dir\n";
			mkdir ("$homedir/logs/$dir") or warn "can't mkdir $homedir/logs/$dir: $!";
		}

		# Does our filename already exist?
		my $file = "error.html";
		if ($autologid == 0) {
			my $i = 1;
			$file = join ("",$year,$mon,$day) . "-$i.html";
			while (-f "$homedir/logs/$dir/$file") {
				$i++;
				$file = join ("",$year,$mon,$day) . "-$i.html";
			}
			$autologid = $i;
		}
		else {
			$file = join ("",$year,$mon,$day) . "-$autologid.html";
		}

		# Save the HTML.
		&saveHTML ("$homedir/logs/$dir/$file");
	}
}

sub saveHTML {
	my $file = shift;

	# Save as HTML.
	my (@lines) = reverse(@xhtml);
	open (SAVE, ">$file");
	print SAVE "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" "
		. "\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n"
		. "<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"EN\">\n"
		. "<head>\n"
		. "<title>Cyan Chat Transcript | Perl CyanChat Client $VERSION</title>\n"
		. "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n"
		. "<meta name=\"Generator\" content=\"Perl CyanChat Client $VERSION\" />\n"
		. "<style type=\"text/css\">\n"
		. "body {\n"
		. "  background-color: $config{background};\n"
		. "  margin: 5px;\n"
		. "  font-family: Arial,Helvetica,sans-serif;\n"
		. "  font-size: small;\n"
		. "  color: $config{foreground}\n"
		. "}\n"
		. ".message {\n"
		. "  display: block;\n"
		. "  color: $config{foreground}\n"
		. "}\n"
		. ".timestamp {\n"
		. "  color: $config{foreground};\n"
		. "  font-size: smaller\n"
		. "}\n"
		. ".user {\n"
		. "  color: $config{usercolor}\n"
		. "}\n"
		. ".echo {\n"
		. "  color: $config{echocolor}\n"
		. "}\n"
		. ".admin {\n"
		. "  color: $config{admincolor}\n"
		. "}\n"
		. ".guest {\n"
		. "  color: $config{guestcolor}\n"
		. "}\n"
		. ".server {\n"
		. "  color: $config{servercolor}\n"
		. "}\n"
		. ".client {\n"
		. "  color: $config{clientcolor}\n"
		. "}\n"
		. ".private {\n"
		. "  color: $config{privatecolor}\n"
		. "}\n"
		. ".action {\n"
		. "  color: $config{actioncolor}\n"
		. "}\n"
		. "</style>\n"
		. "</head>\n"
		. "<body>\n"
		. "<div class=\"admin\"><b>Transcript saved on " . localtime(time()) . "</b></div>\n\n"
		. (join ("\n\n",@lines) )
		. "</body>\n"
		. "</html>";
	close (SAVE);
}

sub prefs {
	if (exists $windows{__prefs__}) {
		$windows{__prefs__}->focusForce;
	}
	else {
		$helpPage = "general.html"; # The help page if we click for help.

		$windows{__prefs__} = $mw->Toplevel (
			-title => 'Preferences',
		);
		$windows{__prefs__}->geometry ('580x400');
		$windows{__prefs__}->Icon (-image => $IMAGE{worlds});

		$windows{__prefs__}->bind ('<Destroy>', sub {
			delete $windows{__prefs__};
		});

		# Create the button frame.
		my $btnFrame = $windows{__prefs__}->Frame (
		)->pack (-side => 'bottom', -fill => 'x');
		my $prefsFrame = $windows{__prefs__}->Frame (
		)->pack (-side => 'bottom', -fill => 'both', -expand => 1);

		# Draw the window buttons.
		$btnFrame->Button (
			-text => 'Help',
			-command => sub {
				&help ($helpPage);
			},
		)->pack (-side => 'right', -padx => 10, -pady => 5);
		$btnFrame->Button (
			-text => '   Apply   ',
			-command => sub {
				# Save our configuration.
				&savePrefs;
				&bindChatTags;
			},
		)->pack (-side => 'right', -padx => 15, -pady => 5);
		$btnFrame->Button (
			-text => '   Cancel   ',
			-command => sub {
				# Cancel anything we may have changed.
				&initConfig("cancel");
				$windows{__prefs__}->destroy;
			},
		)->pack (-side => 'right', -padx => 0, -pady => 5);
		$btnFrame->Button (
			-text => '   OK   ',
			-command => sub {
				# Commit the changes.
				&savePrefs;
				&bindChatTags;
				$windows{__prefs__}->destroy;
			},
		)->pack (-side => 'right', -padx => 5, -pady => 5);

		# Draw the tab frame.
		my $tabFrame = $prefsFrame->NoteBook (
			-font => $FONT,
		)->pack (-fill => 'both', -expand => 1);

		######################
		## General          ##
		######################

		my $genTab = $tabFrame->add ("general",
			-label => "General",
			-raisecmd => sub {
				$helpPage = "general.html";
			},
		);

			my $apLabFrame = $genTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Appearance',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $apFrame = $apLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labMainFont = $apFrame->Label (
					-text => 'Main Font Face:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 0, -sticky => 'ne');

				$apFrame->Entry (
					-textvariable => \$config{dialogfont},
					-foreground   => '#000000',
					-background   => '#FFFFFF',
					-width        => 20,
					-font         => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 0, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labMainFont,
					-msg => "The font family used on most buttons and "
						. "text entry boxes in the entire program.",
				);

				my $labFontSize = $apFrame->Label (
					-text => 'Font Size:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 1, -sticky => 'ne');

				$apFrame->Entry (
					-textvariable => \$config{fontsize},
					-foreground   => '#000000',
					-background   => '#FFFFFF',
					-width        => 4,
					-font         => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 1, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labFontSize,
					-msg => "The font size (in pixels) of most buttons "
						. "and text boxes in this program.",
				);

				my $labDialogFlow = $apFrame->Label (
					-text => 'Dialog Flow:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 2, -sticky => 'ne');

				my $labReverse = $apFrame->Radiobutton (
					-variable => \$config{reversechat},
					-text     => 'New messages on top (default CC behavior)',
					-value    => 1,
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 2, -sticky => 'nw');

				my $labNormal = $apFrame->Radiobutton (
					-variable => \$config{reversechat},
					-text     => 'New messages on bottom',
					-value    => 0,
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 3, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labDialogFlow,
					-msg => "These options control where new messages appear "
						. "in the dialog window.",
				);
				$tipper->attach ($labReverse,
					-msg => "New messages will appear on top, which mimics "
						. "the default CC behavior.",
				);
				$tipper->attach ($labNormal,
					-msg => "New messages will appear on bottom, which mimics "
						. "most traditional chat programs.",
				);

				my $labDisplayOpts = $apFrame->Label (
					-text => 'Display Options:',
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 4, -sticky => 'ne');

				my $labOrientation = $apFrame->Checkbutton (
					-variable => \$config{orientation},
					-text     => 'Reverse orientation (requires restart)',
					-onvalue  => 'bottom',
					-offvalue => 'top',
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 4, -sticky => 'nw');

				my $labNotify = $apFrame->Checkbutton (
					-variable => \$config{notifyanimate},
					-text     => 'Animate the window titles when new messages arrive',
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 5, -sticky => 'nw');

				my $labAutolog = $apFrame->Checkbutton (
					-variable => \$config{autologging},
					-text     => 'Automatically log all transcripts',
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 6, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labDisplayOpts,
					-msg => "Miscellaneous display options.",
				);
				$tipper->attach ($labOrientation,
					-msg => "When enabled, the text-entry box will appear below "
						. "the chat dialog window, instead of on top (this "
						. "mimics traditional chat programs).",
				);
				$tipper->attach ($labNotify,
					-msg => "When a new message arrives and PCCC is minimized, "
						. "the title will animate to get your attention.",
				);
				$tipper->attach ($labAutolog,
					-msg => "When checked, all messages get automatically logged to "
						. "the \"logs\" folder,\n"
						. "sorted by date (yyyy-mm-dd) format.",
				);

			my $loginLabFrame = $genTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Nickname Settings',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $loginFrame = $loginLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labNickname = $loginFrame->Label (
					-text => "Default Nickname:",
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 0, -sticky => 'ne');

				$loginFrame->Entry (
					-textvariable => \$config{nickname},
					-foreground   => '#000000',
					-background   => '#FFFFFF',
					-width        => 20,
					-font         => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 0, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labNickname,
					-msg => "This nickname will be pre-entered in the Name: "
						. "box on the chat window.",
				);

				my $labAutoJoin = $loginFrame->Checkbutton (
					-variable => \$config{autojoin},
					-text     => "Automatically join chat when connected",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 0, -row => 1, -columnspan => 2, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labAutoJoin,
					-msg => "When enabled, and when there's a Name entered, "
						. "you will automatically join the chat when you "
						. "connect.",
				);

		######################
		## Connection       ##
		######################

		my $connTab = $tabFrame->add ("conn",
			-label => "Connection",
			-raisecmd => sub {
				$helpPage = "connection.html";
			},
		);

			my $servLabFrame = $connTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Server Settings',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $servFrame = $servLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labHost = $servFrame->Label (
					-text => "CyanChat Host:",
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 0, -sticky => 'ne',);

				$servFrame->Entry (
					-textvariable => \$config{chathost},
					-foreground   => '#000000',
					-background   => '#FFFFFF',
					-width        => 20,
					-font         => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 0, -sticky => 'nw');

				$servFrame->Label (
					-text => "Default: cho.cyan.com",
					-font => $FONT,
				)->grid (-column => 2, -row => 0, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labHost,
					-msg => "The server (host) name of a CyanChat server.",
				);

				my $labPort = $servFrame->Label (
					-text => "Port:",
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 1, -sticky => 'ne');

				$servFrame->Entry (
					-textvariable => \$config{chatport},
					-foreground   => '#000000',
					-background   => '#FFFFFF',
					-width        => 20,
					-font         => $FONT,
					-highlightthickness => 0,
				)->grid (-column => 1, -row => 1, -sticky => 'nw');

				$servFrame->Label (
					-text => "Default: 1812\n"
						. "Testing: 1813",
					-font => $FONT,
				)->grid (-column => 2, -row => 1, -sticky => 'nw');

				# Balloon Tooltip.
				$tipper->attach ($labPort,
					-msg => "The port number that the CC server listens on.",
				);

				my $labAutoConnect = $servFrame->Checkbutton (
					-variable => \$config{autoconnect},
					-text     => "Automatically connect when PCCC starts",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 2, -columnspan => 3, -sticky => 'nw');

				my $labReconnect = $servFrame->Checkbutton (
					-variable => \$config{reconnect},
					-text     => "Attempt to reconnect when disconnected",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 3, -columnspan => 3, -sticky => 'nw');

				# Balloon Tooltips.
				$tipper->attach ($labAutoConnect,
					-msg => "When checked, PCCC will attempt to connect to CyanChat "
						. "when it starts up.",
				);
				$tipper->attach ($labReconnect,
					-msg => "When checked, PCCC will attempt once to reconnect to the "
						. "server is the connection is interrupted.",
				);

		######################
		## Color Scheme     ##
		######################

		my $colorTab = $tabFrame->add ("colors",
			-label => "Colors",
			-raisecmd => sub {
				$helpPage = "colors.html";
			},
		);

			my $colLabFrame = $colorTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Chat Colors',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'both', -expand => 1);

			my $colFrame = $colLabFrame->Scrolled ("Pane",
				-scrollbars => 'e',
			)->pack (-side => 'top', -fill => 'both', -expand => 1, -pady => 2);

				# Draw the colors.
				my @types = (
					"h::PCCC Interface",

					"Window Background Color::windowbg",
					"Window Text Color::windowfg",
					"Button Background Color::buttonbg",
					"Button Text Color::buttonfg",
					"Textbox Background Color::inputbg",
					"Textbox Text Color::inputfg",
					"Disabled Text Color::disabledfg",

					"h::Chat Colors",
					"Dialog Window Background::background",
					"Main Chat Text::foreground",
					"Who List Background::whobg",
					"Hyperlinks::linkcolor",
					"Private Messages::privatecolor",
					"Action Messages::actioncolor",

					"h::Nickname Colors",

					"Normal Nicknames::usercolor",
					"My Nickname Echo::echocolor",
					"Cyan Staff::admincolor",
					"Special Guests::guestcolor",
					"ChatServer::servercolor",
					"ChatClient::clientcolor",
				);

				my $colorRow = 0;
				my %colorButtons = ();
				foreach my $type (@types) {
					my ($label,$var) = split(/::/, $type, 2);

					# Headers?
					if ($label eq "h") {
						# Draw the header in a significant style.
						$colFrame->Label (
							-text   => $var,
							-relief => 'sunken',
							-border => 2,
							-font   => [
								@{$FONT},
								-weight => 'bold',
							],
						)->grid (-column => 0, -row => $colorRow,
						-columnspan => 2, -sticky => 'ew', -ipady => 2);
					}
					else {
						# Draw the label first.
						$colFrame->Label (
							-text => "$label:",
							-font => $FONT,
						)->grid (-column => 0, -row => $colorRow, -sticky => 'e');

						# Now draw the color preview.
						$colorButtons{$var} = $colFrame->Button (
							-text => "xxxxxx",
							-font => $FONT,
							-foreground => $config{$var},
							-background => $config{$var},
							-activeforeground => $config{$var},
							-activebackground => $config{$var},
							-command    => [ sub {
								my $var = shift;
								my $new = $windows{__prefs__}->chooseColor (
									-title => 'Choose Color',
									-initialcolor => $config{$var},
								);

								return unless defined $new;
								$config{$var} = $new;

								$colorButtons{$var}->configure (
									-foreground => $new,
									-background => $new,
									-activeforeground => $new,
									-activebackground => $new,
								);
							}, $var ],
						)->grid (-column => 1, -row => $colorRow, -sticky => 'nw');
					}
					$colorRow++;
				}

		######################
		## Ignored Users    ##
		######################

		my $ignoreTab = $tabFrame->add ("ignore",
			-label => "Ignored Users",
			-raisecmd => sub {
				&refreshIgnoreLists();
				$helpPage = "ignorelist.html";
			},
		);

			my $ignoreLabFrame = $ignoreTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Ignored Users',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $ignoreFrame = $ignoreLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

			$ignoreFrame->Label (
				-text => 'Use this window to modify your ignore list.',
				-font => $FONT,
			)->grid (-column => 0, -row => 0, -sticky => 'w');

			my $labOnlineUsers = $ignoreFrame->Label (
				-text => 'Online Users:',
				-font => [
					@{$FONT},
					-weight => 'bold',
				],
			)->grid (-column => 0, -row => 1, -sticky => 'n');

			my $labIgnoredUsers = $ignoreFrame->Label (
				-text => 'Ignored Users:',
				-font => [
					@{$FONT},
					-weight => 'bold',
				],
			)->grid (-column => 1, -row => 1, -sticky => 'n');

			$pOnlineList = $ignoreFrame->Scrolled ("Listbox",
				-scrollbars => "e",
				-background => '#FFFFFF',
				-foreground => '#000000',
				-highlightthickness => 0,
				-selectbackground => '#FFFF00',
				-selectforeground => '#000000',
				-height     => 6,
				-width      => 20,
				-font       => $FONT,
			)->grid (-column => 0, -row => 2, -sticky => 'n');

			$pIgnoreList = $ignoreFrame->Scrolled ("Listbox",
				-scrollbars => "e",
				-background => '#FFFFFF',
				-foreground => '#000000',
				-highlightthickness => 0,
				-selectbackground => '#FFFF00',
				-selectforeground => '#000000',
				-height     => 6,
				-width      => 20,
				-font       => $FONT,
			)->grid (-column => 1, -row => 2, -sticky => 'n');

			my $btnIgnore = $ignoreFrame->Button (
				-text => 'Ignore Selected',
				-font => $FONT,
				-command => sub {
					my $selected = $pOnlineList->get (
						($pOnlineList->curselection)[0]
					);
					print "selected: $selected\n";
					my ($name,$addr) = split(/:/, $selected, 2);
					&ignoreUser (undef,$name);
					&refreshIgnoreLists();
				},
			)->grid (-column => 0, -row => 3, -sticky => 'n');

			my $btnUnignore = $ignoreFrame->Button (
				-text => 'Unignore Selected',
				-font => $FONT,
				-command => sub {
					my $selected = $pIgnoreList->get (
						($pIgnoreList->curselection)[0]
					);
					print "selected: $selected\n";
					my ($name,$addr) = split(/:/, $selected, 2);
					&ignoreUser (undef,$name);
					&refreshIgnoreLists();
				},
			)->grid (-column => 1, -row => 3, -sticky => 'n');

			my $btnRefresh = $ignoreFrame->Button (
				-text => 'Refresh Lists',
				-font => $FONT,
				-command => \&refreshIgnoreLists,
			)->grid (-column => 0, -row => 4, -sticky => 'w');

			my $ignOpts = $ignoreFrame->Pane (
			)->grid (-column => 0, -row => 5, -columnspan => 2, -sticky => 'nw');

			my $labStickyIgnore = $ignOpts->Checkbutton (
				-variable => \$config{stickyignore},
				-text     => 'Remember my ignore list.',
				-onvalue  => 1,
				-offvalue => 0,
				-font     => $FONT,
			)->grid (-column => 0, -row => 1, -sticky => 'w');

				my $labMutualIgnores = $ignOpts->Checkbutton (
					-variable => \$config{ignoreback},
					-text     => "Perform mutual ignores",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 2, -sticky => 'w');

				my $labLoudIgnore = $ignOpts->Checkbutton (
					-variable => \$config{loudignore},
					-text     => "Tell me when somebody ignores me",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 1, -row => 1, -sticky => 'w');

				my $labSendIgnore = $ignOpts->Checkbutton (
					-variable => \$config{sendignore},
					-text     => "Send server ignore command when ignoring users",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 1, -row => 2, -sticky => 'w');

			# Balloon Tooltips.
			$tipper->attach ($labOnlineUsers,
				-msg => "This listbox displays the current online users.",
			);
			$tipper->attach ($labIgnoredUsers,
				-msg => "This listbox displays the users you're currently ignoring.",
			);
			$tipper->attach ($btnIgnore,
				-msg => "Click this button to ignore the selected user.",
			);
			$tipper->attach ($btnUnignore,
				-msg => "Click this button to remove the selected user from your "
					. "ignore list.",
			);
			$tipper->attach ($btnRefresh,
				-msg => "Click this button to refresh the lists on this page.",
			);
			$tipper->attach ($labStickyIgnore,
				-msg => "Enable this option to save your Ignore List after you "
					. "shut down PCCC.",
			);
			$tipper->attach ($labMutualIgnores,
				-msg => "Automatically ignore everyone who ignores us.",
			);
			$tipper->attach ($labLoudIgnore,
				-msg => "When enabled, show a message in chat when somebody "
					. "ignores you.",
			);
			$tipper->attach ($labSendIgnore,
				-msg => "When enabled, send the actual Ignore command to "
					. "the CyanChat server (which can then notify the "
					. "target that you are ignoring them).\n"
					. "Server-side ignores can't be unignored without "
					. "disconnecting from the server.",
			);

		######################
		## Sound Effects    ##
		######################

		my $sfxTab = $tabFrame->add ("sfx",
			-label => "Sounds",
			-raisecmd => sub {
				$helpPage = "sounds.html";
			},
		);

			my $sfxLabFrame = $sfxTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Sound Effects',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $sfxFrame = $sfxLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labPlaySounds = $sfxFrame->Checkbutton (
					-variable => \$config{playsounds},
					-text     => "Enable Sound Effects",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 0, -sticky => 'w');

			my $eventLabFrame = $sfxTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Events',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $eventFrame = $eventLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labJoinSound = $eventFrame->Checkbutton (
					-variable => \$config{playjoin},
					-text     => "When a user joins the room...",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 0, -sticky => 'w');

				my $labLeaveSound = $eventFrame->Checkbutton (
					-variable => \$config{playleave},
					-text     => "When a user exits the room...",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 1, -sticky => 'w');

				my $labPublicSound = $eventFrame->Checkbutton (
					-variable => \$config{playpublic},
					-text     => "When a message is received...",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 2, -sticky => 'w');

				my $labPrivateSound = $eventFrame->Checkbutton (
					-variable => \$config{playprivate},
					-text     => "When a private message is received...",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 3, -sticky => 'w');

				for (my $i = 0; $i <= 3; $i++) {
					$eventFrame->Label (
						-text => "play",
						-font => [
							@{$FONT},
							-weight => 'bold',
						],
					)->grid (-column => 1, -row => $i, -sticky => 'e');
				}

				# Create a list of wav files from the sfx folder.
				opendir (DIR, "./sfx");
				my @wavs = sort(grep(/\.wav$/i, readdir(DIR)));
				closedir (DIR);

				my $i = 0;
				foreach (qw(joinsound leavesound publicsound privatesound)) {
					my $tmp = $eventFrame->BrowseEntry (
						-variable => \$config{$_},
						-font     => $FONT,
						-options  => [
							@wavs,
						],
					)->grid (-column => 2, -row => $i, -sticky => 'w');
					$tmp->Subwidget("entry")->configure (
						-background => '#FFFFFF',
						-foreground => '#000000',
						-font       => $FONT,
						-width      => 10,
					);
					$eventFrame->Button (
						-text    => 'Play',
						-font    => $FONT,
						-command => [ sub {
							my $sound = shift;
							if (length $config{$sound}) {
								push (@PLAYSOUNDS,$config{$sound});
							}
						}, $_ ],
					)->grid (-column => 3, -row => $i, -sticky => 'w');

					$i++;
				}

		######################
		## Miscellaneous    ##
		######################

		my $miscTab = $tabFrame->add ("misc",
			-label => "Miscellaneous",
			-raisecmd => sub {
				$helpPage = "misc.html";
			},
		);

			my $progLabFrame = $miscTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'External Programs',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $progFrame = $progLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labBrowser = $progFrame->Label (
					-text => "Web Browser Command:",
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 0, -sticky => 'e');

				my $labBrowserCmd = $progFrame->BrowseEntry (
					-variable => \$config{browser},
					-options  => [
						"start",
						"htmlview",
						"open",
					],
					-font     => $FONT,
				)->grid (-column => 1, -row => 0, -sticky => 'w');
				$labBrowserCmd->Subwidget("entry")->configure (
					-background => '#FFFFFF',
					-foreground => '#000000',
					-font       => $FONT,
					-width      => 20,
				);

				my $labMPlayer = $progFrame->Label (
					-text => "Command-line Media Player:",
					-font => [
						@{$FONT},
						-weight => 'bold',
					],
				)->grid (-column => 0, -row => 1, -sticky => 'e');

				# For Windows users, don't even show this option.
				if ($^O =~ /win(32|64)/i) {
					$progFrame->Label (
						-text => "Win32::MediaPlayer",
						-font => $FONT,
					)->grid (-column => 1, -row => 1, -sticky => 'w');
				}
				else {
					my $labMPlayerCmd = $progFrame->Entry (
						-textvariable => \$config{mediaplayer},
						-width        => 20,
						-font         => $FONT,
					)->grid (-column => 1, -row => 1, -sticky => 'w');
				}

				# Balloon Tooltip.
				$tipper->attach ($labBrowser,
					-msg => "Type or select the command-line program for "
						. "viewing web pages.\n"
						. "Windows should use `start`\n"
						. "Linux should use `htmlview`\n"
						. "Mac should use `open`",
				);

			my $miscLabFrame = $miscTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Miscellaneous Options',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $miscFrame = $miscLabFrame->Pane (
			)->pack (-side => 'left', -padx => 15);

				my $labImWindows = $miscFrame->Checkbutton (
					-variable => \$config{imwindows},
					-text     => "Show private messages in new windows",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 0, -sticky => 'w');

				my $labIgnoreServer = $miscFrame->Checkbutton (
					-variable => \$config{blockserver},
					-text     => "Ignore private messages from ChatServer",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 1, -sticky => 'w');

				my $labAction = $miscFrame->Checkbutton (
					-variable => \$config{autoact},
					-text     => "Show *...* messsages as /me actions",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 5, -sticky => 'w');

				my $labTypo = $miscFrame->Checkbutton (
					-variable => \$config{loudtypo},
					-text     => "Highlight typo corrections",
					-onvalue  => 1,
					-offvalue => 0,
					-font     => $FONT,
				)->grid (-column => 0, -row => 6, -sticky => 'w');

				# Balloon Tooltip.
				$tipper->attach ($labIgnoreServer,
					-msg => "Ignores private messages sent by [ChatServer] "
						. "(useful when on debug port 1813)",
				);
				$tipper->attach ($labAction,
					-msg => "Messages starting and ending with a * will get "
						. "displayed as a \"/me\" style message.",
				);
				$tipper->attach ($labTypo,
					-msg => "Messages starting with * will get displayed as a "
						. "\"typo correction\" message.",
				);

			my $defLabFrame = $miscTab->LabFrame (
				-labelside => 'acrosstop',
				-label     => 'Revert to Default Settings',
				-font      => [
					@{$FONT},
					-weight => 'bold',
				],
			)->pack (-fill => 'x');

			my $defFrame = $defLabFrame->Pane (
			)->pack (-side => 'top', -fill => 'x', -expand => 1, -padx => 15);

				$defFrame->Label (
					-text => "Click the button below to revert back to the "
						. "default configuration:",
					-font => $FONT,
				)->pack;

				$defFrame->Button (
					-text => "Reset Configuration",
					-font => $FONT,
					-command => sub {
						# Delete the config file.
						if (-f "$homedir/config.txt") {
							unlink ("$homedir/config.txt");
						}
						# Reload configuration.
						&initConfig("cancel");
						&bindChatTags();

						# Destroy this window.
						$windows{__prefs__}->destroy;

						# Reload this window.
						&prefs();
					},
				)->pack;
	}
}

sub refreshIgnoreLists {
	# Sort and populate the lists.
	$pOnlineList->delete ('0','end');
	$pIgnoreList->delete ('0','end');

	my @lsonline = sort { $a cmp $b } keys %online;
	my @lsignore = sort { $a cmp $b } keys %ignore;

	# Populate the online users list, skip ignored users.
	foreach my $nln (@lsonline) {
		next if exists $ignore{$nln};

		# Get the user's info.
		my ($level,$addr) = split(/\;/, $online{$nln}, 2);

		$pOnlineList->insert ('end',"$nln:$addr");
	}

	# Populate the ignore users list.
	foreach my $nln (@lsignore) {
		print "add ignore: $nln ($online{$nln})\n";
		my ($level,$addr) = split(/\;/, $online{$nln}, 2);
		$pIgnoreList->insert ('end',"$nln:$addr");
	}
}

sub playSound {
	my $option = shift;
	my $sfx = join ("",$option,"sound");
	my $check = join ("","play",$option);

	# See if we're allowed to play this sound.
	my $allowed = 1;

	# If the global configuration is disabled, don't allow.
	if ($config{playsounds} == 0) {
		$allowed = 0;
	}

	# If we're muting the sounds temporarily, don't allow.
	if ($mutesfx == 1) {
		$allowed = 0;
	}

	# If this particular event is disabled, don't allow.
	if ($config{$check} == 0) {
		$allowed = 0;
	}

	# If the file doesn't exist, don't allow.
	if (!-f "./sfx/$config{$sfx}") {
		$allowed = 0;
	}

	# If allowed, play it.
	if ($allowed) {
		push (@PLAYSOUNDS,$config{$sfx});
	}

	return $allowed;
}

sub help {
	my $page = shift || "index.html";

	if (exists $windows{__help__}) {
		$windows{__help__}->focusForce;
		&helpPage ($page);
	}
	else {
		@helphistory = ();

		$windows{__help__} = $mw->Toplevel (
			-title => 'PCCC Help',
		);
		$windows{__help__}->geometry ('550x400');
		$windows{__help__}->Icon (-image => $IMAGE{worlds});

		$windows{__help__}->bind ('<Destroy>', sub {
			$htmlhelp = undef;
			delete $windows{__help__};
		});

		# Draw the toolbar frame.
		my $tbFrame = $windows{__help__}->Frame (
			-borderwidth => 2,
			-relief      => 'raised',
		)->pack (-side => 'top', -fill => 'x');

		# Toolbar buttons.
		my $btnContents = $tbFrame->Button (
			-text => "Contents",
			-font => $FONT,
			-command => sub {
				&helpPage ("index.html");
			},
		)->pack (-side => 'left');
		my $btnBack = $tbFrame->Button (
			-text => "Back",
			-font => $FONT,
			-command => sub {
				&helpBack;
			},
		)->pack (-side => 'left');
		my $btnExit = $tbFrame->Button (
			-text => "Close",
			-font => $FONT,
			-command => sub {
				$windows{__help__}->destroy;
			},
		)->pack (-side => 'left');

		# Main frame.
		my $mainFrame = $windows{__help__}->Frame (
		)->pack (-fill => 'both', -expand => 1);

		# HTML widget.
		$htmlhelp = $mainFrame->Scrolled ("HyperText",
			-scrollbars   => 'e',
			-wrap         => 'word',
			-titlecommand => \&helpTitle,
			-linkcommand  => \&helpLink,
		)->pack (-fill => 'both', -expand => 1);

		# Show the requested page.
		&helpPage ($page);
	}
}

sub helpPage {
	my $page = shift;
	my $nohistory = shift || 0;

	if (!-f "./docs/$page") {
		$page = "404.html";
	}

	open (PAGE, "./docs/$page");
	my @html = <PAGE>;
	close (PAGE);
	chomp @html;

	my $code = join ("\n",@html);
	$code =~ s/%VERSION%/$VERSION/ig;
	$code =~ s/%DATE%/$MODIFIED/ig;
	$code =~ s/%CC%/$Net::CyanChat::VERSION/ig;
	$code =~ s/%HTML%/$Tk::HyperText::VERSION/ig;

	print "Load help document $page\n";
	unless ($nohistory) {
		push (@helphistory, $page);
		shift(@helphistory) until scalar(@helphistory) <= 25;
	}

	if (defined $htmlhelp) {
		$htmlhelp->clear;
		$htmlhelp->insert ('end',$code);
	}
}

sub helpBack {
	if (scalar(@helphistory)) {
		my $back = pop(@helphistory);
		&helpPage ($back,1);
	}
}

sub helpTitle {
	my ($widget,$title) = @_;
	if (defined $windows{__help__}) {
		if (length $title) {
			$windows{__help__}->title ("$title - PCCC Help");
		}
		else {
			$windows{__help__}->title ("PCCC Help");
		}
	}
}

sub helpLink {
	my ($widget,$href,$target) = @_;

	if ($target eq "_blank") {
		push (@HYPERLINKLIST, $href);
	}
	else {
		&helpPage ($href);
	}
}
