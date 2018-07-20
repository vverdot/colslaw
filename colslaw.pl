#!/usr/bin/perl

# Disabled strict to have colslaw working as standalone script
# + and urxvt extension at the same time. (FIX welcome)
#use strict;
use warnings;

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev bundling);
use Tie::File;

=pod
    TODO:
    - detect variants / switch between them
    -? favorites
    - warning on useless themes / invalid ones
    - option to write in xresources / install theme
    -? option to test for color support (term + env + xresources)
    - implement --legend option
    - Xresources-only config?
=cut

# Setup some gobal vars
my $homeDir = $ENV{'HOME'};

my $colslawDir =  $ENV{'COLSLAW_HOME'};
(defined $colslawDir) or $colslawDir = $homeDir . '/.colslaw';

my $configFile = $colslawDir . '/config';
my %config = ();
load_config() or warn "Failed to load config file $configFile\n";

my $themesDir = $ENV{'COLSLAW_THEMES'};
(defined $themesDir) or $themesDir = defined $config{"themesPath"} ? $config{"themesPath"} : $colslawDir . '/themes';

# REF: http://pod.tst.eu/http://cvs.schmorp.de/rxvt-unicode/doc/rxvt.7.pod#XTerm_Operating_System_Commands
# what about cursorColor, pointerColor, throughColor, underlineColor ?
my %OSC_CODES = (
   "foreground" => '10',
   "background" => '11',
   "cursorColor" => '12',
   "!mouse_background" => '13',
   "!highlightColor" => '17',
   "!highlightTextColor" => '19',
   "colorIT" => '704',
   "colorBD" => '706',
   "colorUL" => '707',
   "borderColor" => '708'
);

my $OSC_COLOR = '4';
my $OSC_ESC = "\e]";
my $OSC_BEL = "\a";

my %resources;
my @unknown;
my $status;

# CLI Options

my $opt_verbose = 0;
my $opt_dryrun  = 0;
my $opt_quiet   = 0;

# URxvt extension mode?
my $urxvt_mode = 0;

# Call Main if called directly
# Let distinguish between direct execution
#+ and urxvt extension.
unless (caller) {

    $urxvt_mode = 0;

    GetOptions(
        'verbose|v' => \$opt_verbose,
        'dry-run|n' => \$opt_dryrun
    ) or die("Check script usage with --help.\n");

    Main( @ARGV );
    exit;
}

sub load_config {
    open(FH, '<', $configFile) or return 0;
   
    while(<FH>){
        chomp;                  # no newline
        s/^#.*//;               # no comments
        s/^\s+//;               # no leading white
        s/\s+$//;               # no trailing white
        next unless length;     # anything left?

        # parse configuration
        # https://regex101.com/r/6PvVoT/2
        if ( $_ =~ m/^(\S+)\s*=\s*(".+"|\S+)$/ ) {
            #print "[CONFIG] $1 => $2\n";
            my $name = $1;
            my $value = $2;
            $value =~ s/^\"//;
            $value =~ s/\"$//;
            $config{$name} = "$value";
            next;
        }
    } 
    
    close(FH);

    return 1;
}

sub write_config {
    
    my ($name, $value) = @_;
    my $found = 0;

    chomp $value;
    
    # Are double quotes required?
    if ($value =~ m/\S(\ |\t)+\S/) {
        $value = "\"$value\"";
    }

    # Update cache too
    $config{$name} = $value;

    tie my @configs, 'Tie::File', $configFile or return 0;
    
    for (@configs) {
        if ( $_ =~ m/^$name\s*=\s*\S+/ ) {
            $_ = "$name=$value";
            $found = 1;
            last;
        }
    }

    push @configs, "$name=$value" unless $found;

    untie @configs;
}

#######################
# urxvt specific subs #
#######################


sub on_start {
    my ($self) = @_;
   
    # Force option
    $opt_quiet = 1;
    $urxvt_mode = 1;

    #$self->{"current"} = $config{"theme"};
    #$self->cmd_parse("\e]10;#ffffff\a");

    urxvt_reset($self, 1);

    ()        
}

sub on_action {
    my ($self, $action) = @_;

    if    ($action eq "reset") { 
        #$self->cmd_parse("\e]10;#ffffff\a");
        #$self->scr_add_lines($themesDir);
        #$self->scr_add_lines("\e]10;#ffffff\a");

        urxvt_reset($self);        
    }
    elsif ($action eq "previous") {
        urxvt_browse($self, 1);
        urxvt_ov($self, $self->{'current'}, 6);
    }
    elsif ($action eq "next") {
        urxvt_browse($self, -1);
        urxvt_ov($self, $self->{'current'}, 6);
    }
    elsif ($action eq "set") {
        urxvt_set($self);
        urxvt_ov($self, "$self->{'current'} [default]", 6);
    }
    else     { warn "else" }

    ()
}

sub urxvt_ov {
    my ($self, $msg, $duration) = @_;
    
    # Somehow invert the colors for clear overlay display
    my $rend = urxvt::OVERLAY_RSTYLE;
    $rend = urxvt::SET_FGCOLOR $rend, 1;
    $rend = urxvt::SET_BGCOLOR $rend, 0;
    
    my $term = $self->{'term'};
    $term->{'colslaw'} = {
      ov => $term->overlay(-1, -1, length($msg) + 4 , 3, $rend, 0),
      to => urxvt::timer
      ->new
      ->start(urxvt::NOW + $duration)
      ->cb(sub {
        delete $term->{'colslaw'};
      }),
    };
    $term->{'colslaw'}->{'ov'}->set(2, 1, $msg);
}

sub urxvt_set {
    my ($self) = @_;
    save_theme($self->{"current"});
}

sub urxvt_reset {
    my ($self, $starting) = @_;

    if (not load_config()) {
        warn "Failed to load config file $configFile\n";
        return 0;
    }

    load_file(theme_file($config{"theme"}));
    # TODO: test if load_file() was successful!
    $self->{"current"} = $config{"theme"};

    $self->cmd_parse(get_colorscheme_cmd());
   
    urxvt_ov($self, $self->{"current"}, 6) unless $starting; 

    return 1;
}

sub urxvt_browse {
    my ($self, $dir) = @_;

    # TODO: optimization
    my @themes = list_themes();

    my $idx = 0;
    my $defaultIdx = -1;
    my $nb_themes = scalar @themes;

    # Find current position
    if (defined $self->{"current"}) {
        for (my $i=0; $i < $nb_themes; $i++) {
            my $filename = $themes[$i];
            chomp $filename;
            my $theme_name = theme_name($filename);

            if ($self->{"current"} eq $theme_name) {
                $defaultIdx = $i;
                last;
            }
         }  
    }

    $idx = ($defaultIdx + 1 * $dir) unless ($defaultIdx == -1);
    # Fix index
    if ($idx == -1) {
       $idx = $nb_themes - 1;
    } elsif ($idx == $nb_themes) {
        $idx = 0;
    }
    
    my $filename = $themes[$idx];
    chomp $filename;
    my $theme_name = theme_name($filename);

    load_file($filename);

    # TODO: test if load_file() was successful!
    $self->{"current"} = $theme_name;

    $self->cmd_parse(get_colorscheme_cmd());
    
    return 1;
}

################
# colslaw subs #
################


sub reset_resources {
    %resources = ();
    @unknown = ();
    $status = '';
}

sub osc_cmd {
    my ($Ps, $Pt) = @_;

    return "$OSC_ESC$Ps;$Pt$OSC_BEL";
}

sub osc_color_cmd {
    my ($color, $value) = @_;
    
    $color =~ s/^color//;

    my $Pt = "$color;$value";

    return osc_cmd($OSC_COLOR, $Pt);
}

# Return the list of installed themes
sub list_themes {
    #my @value = qx{find $themesDir -type f,l | sed 's|^$themesDir/||'};
    my @value = qx{find -L $themesDir -type f,l};
    return @value;
}

# Theme file to Theme name
sub theme_name {
    my ($theme) = @_;
    $theme =~ s|^$themesDir/||;
    chomp $theme;
    return $theme;
}

# Theme name to Theme file
sub theme_file {
    my ($theme) = @_;
    $theme = $themesDir . '/' . $theme;
    chomp $theme;
    return $theme;
}

sub get_colorscheme_cmd {

    my $cs_cmd = "";

    foreach ( keys %resources ) {
        if ( $_ =~ m/^color(\d{1,3})$/ ) {
            $cs_cmd .= osc_color_cmd($_ , $resources{$_});
        } else {
            $cs_cmd .= osc_cmd($OSC_CODES{$_}, $resources{$_});
        }
    }
    
    return $cs_cmd;
}

sub load_colorscheme {
    #print "$_ $resources{$_}\n" for (keys %resources);

    foreach ( keys %resources ) {
        if ( $_ =~ m/^color(\d{1,3})$/ ) {
            print osc_color_cmd($_ , $resources{$_});
        } else {
            print osc_cmd($OSC_CODES{$_}, $resources{$_});
        }
    }
}

sub load_file {
    my ($filename) = @_;
    
    # Clear collected resources
    reset_resources();
    
    my %definitions;

    open(my $FH, '<', $filename) or die "$! $filename\n";
  
    # leaning Perl the hard way :p
    # $_ not localized in while loops...
    # http://www.perlmonks.org/?node=65287%20 
    while(local $_ = <$FH>){

        # basic cleanup
        chomp;                  # no newline
        s/!.*//;                # no comments
        s/^\s+//;               # no leading white
        s/\s+$//;               # no trailing white

        # parse #defines
        # https://regex101.com/r/2t1ekK/3/
        if ( $_ =~ m/^#define\s+(\S+)\s+(#\S+)$/ ) {
            $definitions{$1} = $2;
            next;
        }  
        s/^#.*//;                # no comments
        next unless length;     # anything left?
        
        # parse resource
        if ( $_ =~ m/^(\S+\.|\*\.?)?(\S+)\s*:\s*(.+)/ ) {
            add_resource($2, $3, %definitions);
            next;
        } else {
            print "Warning: cannot parse resource line < $_ > !\n";
        }
    }

    close($FH);  
    #print "$_ $defines{$_}\n" for (keys %defines);
   
    fix_colorscheme();

    if ($opt_verbose and not $urxvt_mode and not $opt_quiet) {
        print "$filename: [$status] \n";
        if ( @unknown ) {
            foreach( @unknown ) {
                print "  (ignored) $_ \n"; 
            }
        }
    }

    # TODO: Do not load on parsing error (and with no --force)
    load_colorscheme() unless $opt_dryrun or $urxvt_mode;

}

sub add_resource {
    my ($name, $value, %definitions) = @_;

    #if ( not grep { $name eq $_ } @supported_fields ) {
    if ( not defined $OSC_CODES{$name} ) {

        # Is it a color?
        if ( $name =~ m/^color(\d{1,3})$/ ) {
            # TODO: Should I support beyond?
            if ( int $1 > 15 ) {
                push @unknown, "$name: $value";
                $status .= 'E';
                return 0;
           }
        } else {
            push @unknown, "$name: $value";
            $status .= '-';
            return 0;
        }
    }

    if ( $value =~ m/^#[[:xdigit:]]{6}$/ ) {
        $resources{$name} = $value;
        $status .= '.';
    } else {
        # No HEX stuff, check if defined
        if ( exists $definitions{$value} ) {
            $resources{$name} = $definitions{$value};
            $status .= '.';
        }
        else {
            $status .= '!';
            push @unknown, "$name: $value";
            return 0;
        }
    }

    return 1;
}

sub fix_colorscheme {
    # if border not present, use background
    if ( not $resources{"borderColor"} ) {
        my $bcolor = $resources{"background"};
        if (defined $bcolor) { 
            $resources{"borderColor"} = $bcolor;
            $status .= '+';
        }
    }
}

sub save_theme {
    my ($theme_name) = @_;
    write_config("theme", $theme_name);   
}

sub cmd_reset {

    my $theme_name = $config{"theme"};

    if (defined $theme_name) {
        reset_resources();
        load_file(theme_file($theme_name));
    } else { die "Cannot reset, no default theme in config file.\n" }
}

sub cmd_load {
    my ($theme_name) = @_;

    if (defined $theme_name) {
        reset_resources();
        load_file(theme_file($theme_name));
    } else { die "Theme name missing, check usage with --help\n" }

}

sub cmd_set {

    my ($theme_name) = @_;

    if (defined $theme_name) {
        reset_resources();
        load_file(theme_file($theme_name));
        save_theme($theme_name) unless $opt_dryrun;
    } else { die "Theme name missing, check usage with --help\n" }
}

sub cmd_list {

    # Force dry-run mode
    $opt_dryrun = 1;

    my @themes = list_themes();

    if ($opt_verbose) {
        # Disable verbose to manually control it
        $opt_verbose = 0;
        foreach (@themes) {
            chomp;
            load_file($_);
            print theme_name($_) . " [$status] \n";
        }
    } else {
        foreach (@themes) { print theme_name($_) . "\n" }
    }
}

sub cmd_show {
    my @themes = list_themes();

    my $idx = 0;
    my $defaultIdx = -1;
    my $nb_themes = scalar @themes;
    my $selected = 0;

    # Forced options
    $opt_verbose = 0;
    $opt_dryrun = 0;

    # Set default
    my $default = $config{"theme"};
   
    # Fast Forward
    if (defined $default) {
        for (my $i=0; $i < $nb_themes; $i++) {
            my $filename = $themes[$i];
            chomp $filename;
            my $theme_name = theme_name($filename);

            if ($default eq $theme_name) {
                $defaultIdx = $i;
                last;
            }
         }  
    }

    $idx = $defaultIdx unless ($defaultIdx == -1);

    print "> Themes Showcase ";
    print " (j-k: browse, ENTER: select, t: theme, ESC: quit)\n";

    while (1) {
        my $filename = $themes[$idx];
        chomp $filename;
        my $theme_name = theme_name($filename);

        my $default_flag = ($defaultIdx == $idx) ? "[default]" : "";
        print "\33[2K\r[" . ($idx+1) . "/$nb_themes] $theme_name $default_flag";

        # Preview theme
        #reset_resources();
        load_file($filename);

        system("stty raw -echo");
        my $key_code = ord getc(STDIN);
        system("stty cooked echo");

        if ($key_code == 27 or $key_code == 113) { # ESC or 'q' keys
            print "\n";
            last;
        } elsif ($key_code == 106) { # 'k' key
            $idx++;
        } elsif ($key_code == 107) { # 'j' key
            $idx--;
        } elsif ($key_code == 13) {  # ENTER key
            print "\33[2K\r [" . ($idx+1) . "/$nb_themes] $theme_name [selected]";
            print "\n";
            $selected = 1;
            last;
        } elsif ($key_code == 116) { # 't' key
            save_theme(theme_name($filename));
            print "\33[2K\r [" . ($idx+1) . "/$nb_themes] $theme_name [default]";
            print "\n";
            $selected = 1;
            last;
        } else {
            # DEBUG
            print "\nKEY PRESSED: $key_code\n";
            next;
        }

        # Fix index
        if ($idx == -1) {
           $idx = $nb_themes - 1;
        } elsif ($idx == $nb_themes) {
            $idx = 0;
        }
    }

    cmd_reset() unless $selected;
}

# Main
sub Main {

    # Parse the command
    my $command = shift || 'list';
   
    if      ( $command =~ m/^(list|ls)$/ )      { cmd_list(@_) }
    elsif   ( $command =~ m/^(set|apply)$/ )    { cmd_set(@_) }
    elsif   ( $command =~ m/^(load|preview)$/ ) { cmd_load(@_) }
    elsif   ( $command =~ m/^(showcase|show)$/ ){ cmd_show() }
    elsif   ( $command =~ m/^reset$/ )          { cmd_reset() }
    else    { die "Unknown command \"$command\", check usage with --help\n" }

    exit;

}
