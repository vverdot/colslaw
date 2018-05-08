#!/usr/bin/perl

use strict;
use warnings;

# Setup some gobal vars
my $homeDir = $ENV{'HOME'};

my $colslawDir =  $ENV{'COLSLAW_HOME'};
if (not defined $colslawDir) { $colslawDir = $homeDir . '/.colslaw' }

my $themesDir = $ENV{'COLSLAW_THEMES'};
if (not defined $themesDir) { $themesDir = $colslawDir . '/themes' }

# REF: http://pod.tst.eu/http://cvs.schmorp.de/rxvt-unicode/doc/rxvt.7.pod#XTerm_Operating_System_Commands
# what about cursorColor, pointerColor, throughColor, underlineColor ?
my %OSC_CODES = (
   "foreground" => '10',
   "background" => '11',
   "cursorColor" => '12',
   "!mouse_backgroun" => '13',
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

my $verbose = 1;

# Call Main if called directly
# Let distinguish between direct execution
#+ and urxvt extension.
unless (caller) {
    Main( @ARGV );
    exit;
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
    my ($filename, $dryrun) = @_;

    # Clear collected resources
    reset_resources();

    my %definitions;

    open(FH, '<', $filename) or die $!;
   
    while(<FH>){

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

    close(FH);  
    #print "$_ $defines{$_}\n" for (keys %defines);
   
    fix_colorscheme();

    if ($verbose) {
        print "$filename: [$status] \n";
        if ( @unknown ) {
            foreach( @unknown ) {
                print "  (ignored) $_ \n"; 
            }
        }
    }

    load_colorscheme() unless $dryrun;

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

# Main
sub Main {
    reset_resources();

=pod
    my ($theme_sel) = @_;
    
    my @themes = list_themes();
    
    if (defined $theme_sel) {
        print "Selected theme #$theme_sel\n";
    } else {
        my $idx = 0;
        foreach (@themes) {
            print ++$idx . ". " . theme_name($_);
        }
    }
=cut
    
    my ($theme_sel) = @_;
    
    if (defined $theme_sel) {
        load_file(theme_file($theme_sel));
    } else {
        my @themes = list_themes();
        #foreach (@themes) { print theme_name($_) . "\n" }
        foreach (@themes) {
            chomp;
            #print "$_ \n";
            load_file($_, 1);
        }
    }

    #print "\n";
    #load_file(theme_file("Ollie"));
    
    #load_file(theme_file("base16-greenscreen.Xresources"));
}
