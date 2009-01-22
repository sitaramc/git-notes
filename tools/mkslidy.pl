#!/usr/bin/perl -w
use strict;

not @ARGV and -t and do {
    print STDERR "Usage: wiki_creole.pl < input.txt | $0 > output.html\n";
    exit 1;
};

# make slidy text out of my plain text
# run through wiki_creole, THEN this one

# general guidelines
# - first line is title, next line is subtitle
# - use blank lines around anything that gets interpreted by this guy *after*
# wiki_creole is done
# - images; 

my $SLIDYPATH="../tools";

my $preamble = `cat $SLIDYPATH/slidy.preamble`;

# first line of input file (*.qq) must be the text that goes under the words
# "Qurious Quiz"; for example this could be a date

my ($title, $subtitle);
chomp($title = <>);
chomp($subtitle = <>);
$title =~ s/<.?p>//g;
$subtitle =~ s/<.?p>//g;

$preamble =~ s/#TITLE/$title/;
$preamble =~ s/#SUBTITLE/$subtitle/;
print $preamble;

# now the main stuff
my $in;
{ local $/; $in = <>; }

# dummy tag <n> to create fake "incremental" clauses (possibly a bug in w3c
# slidy.js but I'm using it!)
$in =~ s/\@\@(.*?)\@\@/<n>$1<\/n>/g;
$in =~ s/\@\@/<n>/g;

# incremental lists:
# old logic
# # # "*+" as "bullet" in original becomes <ul><li>+...<li>+...</ul>
# # # but the "class" attribute must be placed in the <ul> preceding
# # $in =~ s/<ul>\s+<li>\+/<ul class=\"incremental\"><li>/g;
# # # clean up the rest of the <li>+
# # $in =~ s/       <li>\+/                          <li>/gx;
# new logic: they are now default
# also we put them on the <li>. If we put them on the <ul> as we used to, it
# requires TWO clicks to show the first element of a sub-list.  Very annoying,
# and the bug goes away if you put the class attribute on the <li>.
$in =~ s/<li>/<li class=\"incremental\">/g;

# speaker notes
# our convention is that all slides start with <h1> (slidy requires that
# anyway), and that at most someone may use an <h3> inside.  Any <h2> (which
# the user specifies by starting with two "=" signs at the start, is deemed to
# be speaker notes and deleted here
$in =~ s/<h2>.*?(?=<h1>|$)//sg;

# image; by default it is centered; you can specify left/right also.
# However, the implementation is different
$in =~ s/
            (
                (?:l:|r:|w\d+%:|h\d+%:) *
                [^ <>]+ \. (png|gif|jpg|jpeg)
            )
        /
            &doimg($1)
        /gex;

print $in;

sub doimg
{
    my $pos_src = shift;
    my $center = ($pos_src !~ /l:|r:|w\d+%:|h\d+%:/);
    my $ret = '';
    my $attr = '';
    $attr .= " align=\"left\""  if $pos_src =~ s/l://;
    $attr .= " align=\"right\"" if $pos_src =~ s/r://;
    $attr .= " width=\"$1%\""   if $pos_src =~ s/w(\d+)%://;
    $attr .= " height=\"$1%\""  if $pos_src =~ s/h(\d+)%://;
    $ret .= "<center>" if $center;
    $ret .= "<img src=\"$pos_src\"";
    # print " style=\"float:$pos_src\"" if $pos_src;
    $ret .= $attr if $attr;
    $ret .= ">";
    $ret .= "</center>" if $center;
    $ret .= "\n";
    return $ret;
}
