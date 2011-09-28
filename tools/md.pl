#!/usr/bin/perl -w -s
use strict;

# derived from wiki_creole.pl
#  - do for markdown wiki_creole.pl did for creole syntax
#  - another difference is that the actual markdown to HTML conversion is done
#  outside this program; it is not done as a module call from within.  So the
#  "debug" mode has no meaning in this program.  FIXME this needs to be
#  removed eventually
#
# FIXME includes some temporary hacks to avoid large scale changes in my
# documents -- these hacks convert creole to markdown first, then the rest of
# the program runs

our $filename=$ARGV[0];
sub myvim
{
    my $msg = shift;
    my $prefix = shift;
    system("gvim -c 'goto " . length($prefix) . "' $filename");
    die "$msg";
}

our $css;       # use "-css" if you need css
our $css_block="<head><style>
    body        { margin-left:  40px;   font-size:  0.9em;  font-family: sans-serif; max-width: 800px; }
    h1          { background: #ffb; margin-left: -30px;   border-bottom: 5px  solid #ccc; }
    h2, h3      { background: #ffb; margin-left: -30px;   border-top:    3px  solid #ddd; }
    h4, h5      { background: #ffb; margin-left: -20px; }
    code        { font-size:    1.1em;  background:  #ddf; }
    pre         { margin-left:  2em;    background:  #ddf; }
    pre code    { font-size:    1.1em;  background:  #ddf; }
</style></head>
";
my $markup;
{ local $/; $markup = <>; }

my $toc = '';
my $ctr = 0;
sub maketoc
{
    my($o, $t) = @_;
    # used to be just '$ctr++;', but now you can specify an anchor for later
    # use elsewhere or it will get auto-generated.  The notation for
    # specifying an anchor is that the first word of $t should match '#\w+'
    # followed by one space
    if ($t =~ /^#(\w+) /) {
        $ctr = $1;
        $t =~ s/^#\w+ //;
    } else {
        ($ctr = $t) =~ s/\W+/_/g;
    }
    $toc .= "&nbsp;" x (4 * length($o));
    $toc .= "<a href=\"#$ctr\">$t</a><br>\n";
    return "$o <a name=\"$ctr\">$t</a>";
}

sub my_creole_markup
{
    my($markup, $debug) = @_;

    # ------------------------------------------------------------------------
    # this is stuff that markdown does not support, but we want to, for now...
    # ------------------------------------------------------------------------

    # superscript; assume no more than one per line
    # FIXME replace with die later
    warn "superscript tags inside code at\n$&" if $markup =~ /^ {8,}.*\^\^/m;
    # FIXME this is expensive to do -- replace with proper "sup" directly in
    # content?
    $markup =~ s(
        (
            ^(\ {0,7}\S.*?(?=\z|\n\ {8}))
        )
    )(
        my $s=$1;
        $s =~ s(\^\^(.*?)\^\^)(<sup>$1</sup>)gs;
        $s;
    )msgex;

    # create table of contents from the first 4 levels
    if ($markup =~ /\[\[TOC ?(\d)?\]\]/)
    {
        my $maxdepth = $1 || 4;
        $markup =~ s/^(#{1,$maxdepth}) (.*)/ &maketoc($1, $2) /mge;
        $markup =~ s/\[\[TOC ?\d?\]\]/$toc/;
    }

#    # remove indentation from first line of "bare", indented, paras.  This is
#    # because we now use CSS for the actual indentation anyway
#    1 while $markup =~ s(
#        (
#          (?:               # one of
#            ^[^\s\d+-].+\n  #   left flush line not starting a bullet
#                |           # or
#            ^\ {8,}\S.*\n   #   an implicit code line (that happens to be the last in its block)
#          )
#          (?:               # followed by
#            (?!\s*$).+\n    #   a NON-blank line
#            # XXX lookout, there's a negative lookahead behind you!
#          )*                # (0 or more of them, actually)
#          \s*\n             # then a BLANK line,
#        )                   # ...is $1
#        \ \ \ \ (?= \S )    # payload is 4 spaces then non-space
#    )(
#        "$1"                # and kill those 4 spaces to make it flush left
#    )mgex;

    return $markup;
}

my $html = my_creole_markup($markup, exists $ENV{D});
# marc-andre
$html =~ s/é/&eacute;/;
$html =~ s/è/&egrave;/;
$html = $css_block . $html if $css;
print $html;
