#!/usr/bin/perl -w
use strict;
use Text::WikiCreole;

my $markup;
{ local $/; $markup = <>; }

my $toc = '';
my $ctr = 0;
sub maketoc
{
    my($o, $t) = @_;
    $ctr++;
    $toc .= "&nbsp;" x (4 * length($o));
    $toc .= "<a href=\"#a$ctr\">$t</a><br>\n";
    return "$o <a name=\"a$ctr\">$t</a>";
}

sub my_creole_markup
{
    my($markup, $debug) = @_;

    # create table of contents from the first 4 levels
    if ($markup =~ /\[\[TOC ?(\d)?\]\]/)
    {
        my $maxdepth = $1 || 4;
        $markup =~ s/^(={1,$maxdepth}) (.*)/ &maketoc($1, $2) /mge;
        $markup =~ s/\[\[TOC ?\d?\]\]/$toc/;
    }

    # create explicit "triple curlies" (TC) based on indentation (each block
    # of 8+ indented lines is one TC block)
    $markup =~ s{
        (                   # explicit TC, to be left as is
            ^ \s* {{{\s*$
                .*?
            \n}}}\s*$
        )
        |
        (                   # implicit TC, to be made explicit
            (               # 8+ indent block to be enclosed in TC
                ^\ {8,}\S       # 8 or more leading spaces, then non-space
                .*?             # everything after that, until...
            )
            (               # the implicit TC block ends, with:
                \Z              # end of string
            |                   #   or
                \n+\ {0,7}\S    # 0-7 indent line to end the implicit TC block
            )
        )
    }{
        $1 && length($1) ? $1 : "\n{{{\n$3\n}}}\n$4"
    }msgex;

    # make explicit "first level blocks" (FLB) as needed (the first 4-indent
    # line that is not inside a bullet list gets a ":" at the start
    $markup =~ s{
        (
            (?:             # explicit TC, to be left as is
                ^ \s* {{{\s*$
                    .*?
                \n}}}\s*$
            )
            |
            (?:             # bulleted list or explicitly indented line, also
                            # to be left alone
                ^ \s* [;:*\#]
                    .*?
                (?: \n\n | \Z )
            )
        )
        |
        (                   # implicit first-level block, to be made explicit
            ^\ {4}              # 4 leading spaces, then
            (
                \S              # a non-space
                .*?             # everything after that, until...
            )
            (?=             # the implicit TC block ends, with:
                \Z              # end of string
            |                   #   or
                ^\s*$           # a blank line
            |                   #   or
                \n+\ {0,3}\S    # 0-3 indent line
            )
        )
    }{
        $1 && length($1) ? $1 : "    :$3"
    }msgex;

    return ( $debug ? $markup : creole_parse $markup );
}

# default is <div style="margin-left: 2em">, but neither html2ps nor a
# cut-paste from firefox to oowriter seem to recognise it and do the right
# thing; they want an old style <blockquote>
creole_tag("ip", "open", "<blockquote>\n");
creole_tag("ip", "close", "</blockquote>\n");
my $html = my_creole_markup($markup, exists $ENV{D});
# marc-andre
$html =~ s/é/&eacute;/;
$html =~ s/è/&egrave;/;
print $html;
