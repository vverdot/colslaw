#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(:config no_ignore_case no_auto_abbrev bundling);
use Tie::File;

=pod
    TODO:
    - browse command (interactive display)
    - reset command
    - detect variants / switch between them
    -? favorites
    - warning on useless themes / invalid ones
    - option to write in xresources / install theme
    -? option to test for color support (term + env + xresources)
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

# Call Main if called directly
# Let distinguish between direct execution
#+ and urxvt extension.
unless (caller) {

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
            $config{$1} = $2;
            next;
        }
    } 
    
    close(FH);

    return 1;
}

sub write_config {
    
    my ($name, $value) = @_;
    my $found = 0;

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


sub on_action {
    my ($self, $action) = @_;

    if    ($action eq "nothing")    { list_themes() }
    elsif ($action eq "test")       { warn "test" }
    else                            { warn "else" }

    ()
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
    my @value = qx{find $themesDir -type f,l};
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
            #print "$2 => $3\n";
            # TODO:
            #  1- test if name is supported (list or color*)
            #  2- test if value is supported (defined keyword or valid hex color)
            add_resource($2, $3, %definitions);
            next;
        } else {
            print "Warning: cannot parse resource line < $_ > !\n";
        }
    }

    close($FH);  
    #print "$_ $defines{$_}\n" for (keys %defines);
   
    fix_colorscheme();

    if ($opt_verbose) {
        print "$filename: [$status] \n";
        if ( @unknown ) {
            foreach( @unknown ) {
                print "  (ignored) $_ \n"; 
            }
        }
    }

    load_colorscheme() unless $opt_dryrun;

}

sub add_resource {
    my ($name, $value, %definitions) = @_;

    #if ( not grep { $name eq $_ } @supported_fields ) {
    if ( not defined $OSC_CODES{$name} ) {

        # Is it a color?
        if ( $name =~ m/^color(\d{1,3})$/ ) {
           if ( int $1 > 255 ) {
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
    write_config("defaultTheme", $theme_name);   
}

sub cmd_set {

    my ($theme_name) = @_;

    defined $theme_name or $theme_name = $config{"defaultTheme"};

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


# Main
sub Main {

    # Parse the command
    my $command = shift || 'list';
   
    if      ( $command =~ m/^(list|ls)$/ )      { cmd_list(@_) }
    elsif   ( $command =~ m/^(set|apply)$/ )    { cmd_set(@_) }
    else    { die "Unknown command \"$command\", check usage with --help\n" }

    exit;

}
