package Text::WikiCreole;
require Exporter;
@ISA = (Exporter);
@EXPORT = qw(creole_parse creole_plugin creole_tag creole_img creole_customimgs
             creole_link creole_barelink creole_customlinks creole_custombarelinks);
use vars qw($VERSION);
use strict;
use warnings;

our $VERSION = "0.07";

sub  strip_head_eq { # strip lead/trail white/= from headings
  $_[0] =~ s/^\s*=*\s*//o;
  $_[0] =~ s/\s*=*\s*$//o;
  return $_[0];
}

sub strip_list {  # strip list markup trickery
  $_[0] =~ s/(?:`*| *)[\*\#]/`/o; 
  $_[0] =~ s/\n(?:`*| *)[\*\#]/\n`/gso; 
  return $_[0]; 
}

# characters that may indicate inline wiki markup
my @specialchars = ('^', '\\', '*', '/', '_', ',', '{', '[', 
                    '<', '~', '|', "\n", '#', ':', ';', '(', '-', '.');
# plain characters - auto-generated below (ascii printable minus @specialchars)
my @plainchars; 

# non-plain text inline widgets
my @inline = ('strong', 'em', 'br',  'esc', 'img', 'link', 'ilink',
              'inowiki', 'sub', 'sup', 'mono', 'u', 'plug', 'plug2', 'tm', 
              'reg', 'copy', 'ndash', 'ellipsis', 'amp');
my @all_inline = (@inline, 'plain', 'any'); # including plain text

# blocks
my @blocks = ('h1', 'h2', 'h3', 'hr', 'nowiki', 'h4', 'h5', 'h6',
              'ul', 'ol', 'table', 'p', 'ip', 'dl', 'plug', 'plug2', 'blank');

# handy - used several times in %chunks
my $eol = '(?:\n|$)'; # end of line (or string)
my $bol = '(?:^|\n)'; # beginning of line (or string)

# user-supplied plugin parser function
my $plugin_function;
# user-supplied link URL parser function
my $link_function;
# user-supplied bare link parser function
my $barelink_function;
# user-supplied image URL parser function
my $img_function;

# initialize once
my $initialized = 0;

my %chunks = (
  top => {
     contains => \@blocks,
  },
  blank => {
    curpat => "(?= *$eol)",
    fwpat => "(?=(?:^|\n) *$eol)",
    stops => '(?=\S)',
    hint => ["\n"],
    filter => sub { return ""; }, # whitespace into the bit bucket
    open => "", close => "",
  },
  p => {
    curpat => '(?=.)',
    stops => ['blank', 'ip', 'h', 'hr', 'nowiki', 'ul', 'ol', 'dl', 'table'],
    hint => \@plainchars,
    contains => \@all_inline,
    filter => sub { chomp $_[0]; return $_[0]; },
    open => "<p>", close => "</p>\n\n",
  },
  ip => {
    curpat => '(?=:)',
    fwpat => '\n(?=:)',
    stops => ['blank', 'h', 'hr', 'nowiki', 'ul', 'ol', 'dl', 'table'],
    hint => [':'],
    contains => ['p', 'ip'],
    filter => sub { 
      $_[0] =~ s/://o; 
      $_[0] =~ s/\n:/\n/so; 
      return $_[0]; 
    },
    open => "<div style=\"margin-left: 2em\">", close => "</div>\n",
  },
  dl => {
    curpat => '(?=;)',
    fwpat => '\n(?=;)',
    stops => ['blank', 'h', 'hr', 'nowiki', 'ul', 'ol', 'table'],
    hint => [';'],
    contains => ['dt', 'dd'],
    open => "<dl>\n", close => "</dl>\n",
  },
  dt => {
    curpat => '(?=;)',
    fwpat => '\n(?=;)',
    stops => '(?=:|\n)',
    hint => [';'],
    contains => \@all_inline,
    filter => sub { $_[0] =~ s/^;\s*//o; return $_[0]; },
    open => "  <dt>", close => "</dt>\n",
  },
  dd => {
    curpat => '(?=\n|:)',
    fwpat => '(?:\n|:)',
    stops => '(?=:)|\n(?=;)',
    hint => [':', "\n"],
    contains => \@all_inline,
    filter => sub { 
      $_[0] =~ s/(?:\n|:)\s*//so; 
      $_[0] =~ s/\s*$//so;
      return $_[0]; 
    },
    open => "    <dd>", close => "</dd>\n",
  },
  table => {
    curpat => '(?= *\|.)',
    fwpat => '\n(?= *\|.)',
    stops => '\n(?= *[^\|])',
    contains => ['tr'],
    hint => ['|', ' '],
    open => "<table>\n", close => "</table>\n\n",
  },
  tr => {
    curpat => '(?= *\|)',
    stops => '\n',
    contains => ['td', 'th'],
    hint => ['|', ' '],
    filter => sub { $_[0] =~ s/^ *//o; $_[0] =~ s/\| *$//o; return $_[0]; },
    open => "    <tr>\n", close => "    </tr>\n",
  },
  td => {
    curpat => '(?=\|[^=])',
    # this gnarly regex fixes ambiguous '|' for links/imgs/nowiki in tables
    stops => '[^~](?=\|(?!(?:[^\[]*\]\])|(?:[^\{]*\}\})))',
    contains => \@all_inline,
    hint => ['|'],
    filter => sub {$_[0] =~ s/^ *\| *//o; $_[0] =~ s/\s*$//so; return $_[0]; },
    open => "        <td>", close => "</td>\n",
  },
  th => {
    curpat => '(?=\|=)',
    # this gnarly regex fixes ambiguous '|' for links/imgs/nowiki in tables
    stops => '[^~](?=\|(?!(?:[^\[]*\]\])|(?:[^\{]*\}\})))',
    contains => \@all_inline,
    hint => ['|'],
    filter => sub {$_[0] =~ s/^ *\|= *//o; $_[0] =~ s/\s*$//so; return $_[0]; },
    open => "        <th>", close => "</th>\n",
  },
  ul => {
    curpat => '(?=(?:`| *)\*[^\*])',
    fwpat => '(?=\n(?:`| *)\*[^\*])',
    stops => ['blank', 'ip', 'h', 'nowiki', 'li', 'table', 'hr', 'dl'],
    contains => ['ul', 'ol', 'li'],
    hint => ['*', ' '],
    filter => \&strip_list,
    open => "<ul>\n", close => "</ul>\n",
  },
  ol => {
    curpat => '(?=(?:`| *)\#[^\#])',
    fwpat => '(?=\n(?:`| *)\#[^\#])',
    stops => ['blank', 'ip', 'h', 'nowiki', 'li', 'table', 'hr', 'dl'],
    contains => ['ul', 'ol', 'li'],
    hint => ['#', ' '],
    filter => \&strip_list,
    open => "<ol>\n", close => "</ol>\n",
  },
  li => {
    curpat => '(?=`[^\*\#])',
    fwpat => '\n(?=`[^\*\#])',
    stops => '\n(?=`)',
    hint => ['`'],
    filter => sub { 
      $_[0] =~ s/` *//o;
      chomp $_[0];
      return $_[0];
    },
    contains => \@all_inline,
    open => "    <li>", close => "</li>\n",
  },
  nowiki => {
    curpat => '(?=\{\{\{ *\n)',
    fwpat => '\n(?=\{\{\{ *\n)',
    stops => "\n\}\}\} *$eol",
    hint => ['{'],
    filter => sub {
      substr($_[0], 0, 3, '');
      $_[0] =~ s/\}\}\}\s*$//o;
      $_[0] =~ s/&/&amp;/go;
      $_[0] =~ s/</&lt;/go;
      $_[0] =~ s/>/&gt;/go;
      return $_[0];
    },
    open => "<pre>", close => "</pre>\n\n",
  },
  hr => {
    curpat => "(?= *-{4,} *$eol)",
    fwpat => "\n(?= *-{4,} *$eol)",
    hint => ['-', ' '],
    stops => $eol,
    open => "<hr />\n\n", close => "",
    filter => sub { return ""; } # ----- into the bit bucket
  },
  h => { curpat => '(?=(?:^|\n) *=)' }, # matches any heading
  h1 => {
    curpat => '(?= *=[^=])',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h1>", close => "</h1>\n\n",
    filter => \&strip_head_eq,
  },
  h2 => {
    curpat => '(?= *={2}[^=])',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h2>", close => "</h2>\n\n",
    filter => \&strip_head_eq,
  },
  h3 => {
    curpat => '(?= *={3}[^=])',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h3>", close => "</h3>\n\n",
    filter => \&strip_head_eq,
  },
  h4 => {
    curpat => '(?= *={4}[^=])',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h4>", close => "</h4>\n\n",
    filter => \&strip_head_eq,
  },
  h5 => {
    curpat => '(?= *={5}[^=])',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h5>", close => "</h5>\n\n",
    filter => \&strip_head_eq,
  },
  h6 => {
    curpat => '(?= *={6,})',
    hint => ['=', ' '], 
    stops => '\n',
    contains => \@all_inline,
    open => "<h6>", close => "</h6>\n\n",
    filter => \&strip_head_eq,
  },
  plain => {
    curpat => '(?=[^\*\/_\,\^\\\\{\[\<\|])',
    stops => \@inline,
    hint => \@plainchars,
    open => '', close => ''
  },
  any => { # catch-all
    curpat => '(?=.)',
    stops => \@inline,
    open => '', close => ''
  },
  br => {
    curpat => '(?=\\\\\\\\)',
    stops => '\\\\\\\\',
    hint => ['\\'],
    filter => sub { return ''; },
    open => '<br />', close => '',
  },
  esc => {
    curpat => '(?=~[\S])',
    stops => '~.',
    hint => ['~'],
    filter => sub { substr($_[0], 0, 1, ''); return $_[0]; },
    open => '', close => '',
  },
  inowiki => {
    curpat => '(?=\{{3}.*?\}*\}{3})',
    stops => '.*?\}*\}{3}',
    hint => ['{'],
    filter => sub {
      substr($_[0], 0, 3, ''); 
      $_[0] =~ s/\}{3}$//o;
      $_[0] =~ s/&/&amp;/go;
      $_[0] =~ s/</&lt;/go;
      $_[0] =~ s/>/&gt;/go;
      return $_[0];
    },
    open => "<tt>", close => "</tt>",
  },
  plug => {
    curpat => '(?=\<{3}.*?\>*\>{3})',
    stops => '.*?\>*\>{3}',
    hint => ['<'],
    filter => sub {
      substr($_[0], 0, 3, ''); 
      $_[0] =~ s/\>{3}$//o;
      if($plugin_function) {
        return &$plugin_function($_[0]);
      }
      return "<<<$_[0]>>>";
    },
    open => "", close => "",
  },
  plug2 => {
    curpat => '(?=\<{2}.*?\>*\>{2})',
    stops => '.*?\>*\>{2}',
    hint => ['<'],
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\>{2}$//o;
      if($plugin_function) {
        return &$plugin_function($_[0]);
      }
      return "<<$_[0]>>";
    },
    open => "", close => "",
  },
  ilink => {
    curpat => '(?=(?:https?|ftp):\/\/)',
    stops => '(?=[[:punct:]]?(?:\s|$))',
    hint => ['h', 'f'],
    filter => sub {
      $_[0] =~ s/^\s*//o;
      $_[0] =~ s/\s*$//o;
      if($barelink_function) {
        $_[0] = &$barelink_function($_[0]);
      }
      return "href=\"$_[0]\">$_[0]"; },
    open => "<a ", close=> "</a>",
  },
  link => {
    curpat => '(?=\[\[[^\n]+?\]\])',
    stops => '\]\]',
    hint => ['['],
    contains => ['href', 'atext'],
    filter => sub {
      substr($_[0], 0, 2, ''); 
      substr($_[0], -2, 2, ''); 
      $_[0] .= "|$_[0]" unless $_[0] =~ tr/|/|/; # text = url unless given
      return $_[0];
    },
    open => "<a ", close => "</a>",
  },
  href => {
    curpat => '(?=[^\|])',
    stops => '(?=\|)',
    filter => sub { 
      $_[0] =~ s/^\s*//o; 
      $_[0] =~ s/\s*$//o; 
      if($link_function) {
        $_[0] = &$link_function($_[0]);
      }
      return $_[0]; 
    },
    open => 'href="', close => '">',
  },
  atext => {
    curpat => '(?=\|)',
    stops => '\n',
    hint => ['|'],
    contains => \@all_inline,
    filter => sub { 
      $_[0] =~ s/^\|\s*//o; 
      $_[0] =~ s/\s*$//o; 
      return $_[0]; 
    },
    open => '', close => '',
  },
  img => {
    curpat => '(?=\{\{[^\{][^\n]*?\}\})',
    stops => '\}\}',
    hint => ['{'],
    contains => ['imgsrc', 'imgalt'],
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\}\}$//o;
      return $_[0];
    },
    open => "<img ", close => " />",
  },
  imgalt => {
    curpat => '(?=\|)',
    stops => '\n',
    hint => ['|'],
    filter => sub { $_[0] =~ s/^\|\s*//o; $_[0] =~ s/\s*$//o; return $_[0]; },
    open => ' alt="', close => '"',
  },
  imgsrc => {
    curpat => '(?=[^\|])',
    stops => '(?=\|)',
    filter => sub { 
      $_[0] =~ s/^\s*//o; 
      $_[0] =~ s/\s*$//o; 
      if($img_function) {
        $_[0] = &$img_function($_[0]);
      }
      return $_[0]; 
    },
    open => 'src="', close => '"',
  },
  strong => {
    curpat => '(?=\*\*)',
    stops => '\*\*.*?\*\*',
    hint => ['*'],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\*\*$//o;
      return $_[0];
    },
    open => "<strong>", close => "</strong>",
  },
  em => {
    curpat => '(?=\/\/)',
    stops => '\/\/.*?(?<!:)\/\/',
    hint => ['/'],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\/\/$//o;
      return $_[0];
    },
    open => "<em>", close => "</em>",
  },
  mono => {
    curpat => '(?=\#\#)',
    stops => '\#\#.*?\#\#',
    hint => ['#'],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\#\#$//o;
      return $_[0];
    },
    open => "<tt>", close => "</tt>",
  },
  sub => {
    curpat => '(?=,,)',
    stops => ',,.*?,,',
    hint => [','],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\,\,$//o;
      return $_[0];
    },
    open => "<sub>", close => "</sub>",
  },
  sup => {
    curpat => '(?=\^\^)',
    stops => '\^\^.*?\^\^',
    hint => ['^'],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/\^\^$//o;
      return $_[0];
    },
    open => "<sup>", close => "</sup>",
  },
  u => {
    curpat => '(?=__)',
    stops => '__.*?__',
    hint => ['_'],
    contains => \@all_inline,
    filter => sub {
      substr($_[0], 0, 2, ''); 
      $_[0] =~ s/__$//o;
      return $_[0];
    },
    open => "<u>", close => "</u>",
  },
  amp => {
    curpat => '(?=\&(?!\w+\;))',
    stops => '.',
    hint => ['&'],
    filter => sub { return "&amp;"; },
    open => "", close => "",
  },
  tm => {
    curpat => '(?=\(TM\))',
    stops => '\(TM\)',
    hint => ['('],
    filter => sub { return "&trade;"; },
    open => "", close => "",
  },
  reg => {
    curpat => '(?=\(R\))',
    stops => '\(R\)',
    hint => ['('],
    filter => sub { return "&reg;"; },
    open => "", close => "",
  },
  copy => {
    curpat => '(?=\(C\))',
    stops => '\(C\)',
    hint => ['('],
    filter => sub { return "&copy;"; },
    open => "", close => "",
  },
  ndash => {
    curpat => '(?=--)',
    stops => '--',
    hint => ['-'],
    filter => sub { return "&ndash;"; },
    open => "", close => "",
  },
  ellipsis => {
    curpat => '(?=\.\.\.)',
    stops => '\.\.\.',
    hint => ['.'],
    filter => sub { return "&hellip;"; },
    open => "", close => "",
  },
);

  
sub parse; # predeclared because it's recursive
      
sub parse {
  my ($tref, $chunk) = @_;
  my ($html, $ch);
  my $pos = 0; my $lpos = 0;
  while(1) {
    if($ch) { # if we already know what kind of chunk this is
      if ($$tref =~ /$chunks{$ch}{delim}/g) { # find where it stops...
        $pos = pos($$tref);                   #     another chunk
      } else {
        $pos = length $$tref;                 #     end of string
      }

      $html .= $chunks{$ch}{open};            # print the open tag
     
      my $t = substr($$tref, $lpos, $pos - $lpos); # grab the chunk
      if($chunks{$ch}{filter}) {   # filter it, if applicable
        $t = &{$chunks{$ch}{filter}}($t);
      }
      $lpos = $pos;  # remember where this chunk ends (where next begins)
      if($t && $chunks{$ch}{contains}) {  # if it contains other chunks...
        $html .= parse(\$t, $ch);         #    recurse.
      } else {
        $html .= $t;                      #    otherwise, print it
      }
      $html .= $chunks{$ch}{close};       # print the close tag
    }

    if($pos && $pos == length($$tref)) { # we've eaten the whole string
      last;
    } else {                             # more string to come
      $ch = undef;
      my $fc = substr($$tref, $pos, 1);     # get a hint about the next chunk
      foreach (@{$chunks{$chunk}{hints}{$fc}}) {
#        print "trying $_ for -$fc- on -" . substr($$tref, $pos, 2) . "-\n";
        if($$tref =~ $chunks{$_}{curpatcmp}) { # hint helped id the chunk
           $ch = $_; last;  
        }
      }
      unless($ch) {                           #  hint didn't help
        foreach (@{$chunks{$chunk}{contains}}) { # check all possible chunks
#          print "trying $_ on -" . substr($$tref, $pos, 2) . "-\n";
          if ($$tref =~ $chunks{$_}{curpatcmp}) { # found one
            $ch = $_; last;
          } 
        }
        last unless $ch;  # no idea what this is.  ditch the rest and give up.
      }
    }
  }
  return $html;  # voila!
}

# compile a regex that matches any of the patterns that interrupt the
# current chunk.
sub delim {
  if(ref $chunks{$_[0]}{stops}) {
    my $regex; 
    foreach(@{$chunks{$_[0]}{stops}}) {
      if($chunks{$_}{fwpat}) {
        $regex .= "$chunks{$_}{fwpat}|";
      } else {
        $regex .= "$chunks{$_}{curpat}|";
      }
    }
    chop $regex;
    return qr/$regex/s;
  } else {
    return qr/$chunks{$_[0]}{stops}/s;
  }
}

# one-time optimization of the grammar - speeds the parser up a ton
sub init {
  return if $initialized;

  $initialized = 1;

  # build an array of "plain content" characters by subtracting @specialchars
  # from ascii printable (ascii 32 to 126)
  my %is_special = map({$_ => 1} @specialchars);
  for (32 .. 126) {
    push(@plainchars, chr($_)) unless $is_special{chr($_)};
  }

  # precompile a bunch of regexes 
  foreach my $c (keys %chunks) {
    if($chunks{$c}{curpat}) { 
      $chunks{$c}{curpatcmp} = qr/\G$chunks{$c}{curpat}/s;
    }
    if($chunks{$c}{stops}) { 
      $chunks{$c}{delim} = delim $c;
    }
    if($chunks{$c}{contains}) { # store hints about each chunk to speed id
      foreach my $ct (@{$chunks{$c}{contains}}) {
        foreach (@{$chunks{$ct}{hint}}) {
          push @{$chunks{$c}{hints}{$_}}, $ct;
        }
      }
    }
  }
}

sub creole_parse {
  return unless defined $_[0] && length $_[0] > 0;
  my $text = $_[0]; 
  init;
  my $html = parse(\$text, "top");
  return $html;
}

sub creole_plugin {
  return unless defined $_[0];
  $plugin_function = $_[0];
}

sub creole_link {
  return unless defined $_[0];
  $link_function = $_[0];
}

sub creole_customlinks {
  $chunks{href}{open} = "";
  $chunks{href}{close} = "";
  $chunks{link}{open} = "";
  $chunks{link}{close} = "";
  delete $chunks{link}{contains};
  $chunks{link}{filter} = sub { 
    if($link_function) {
      $_[0] = &$link_function($_[0]);
    }
    return $_[0];
  }
}

sub creole_barelink {
  return unless defined $_[0];
  $barelink_function = $_[0];
}

sub creole_custombarelinks {
  $chunks{ilink}{open} = "";
  $chunks{ilink}{close} = "";
  $chunks{ilink}{filter} = sub {
    if($barelink_function) {
      $_[0] = &$barelink_function($_[0]);
    }
    return $_[0];
  }
}

sub creole_customimgs {
  $chunks{img}{open} = "";
  $chunks{img}{close} = "";
  delete $chunks{img}{contains};
  $chunks{img}{filter} = sub { 
    if($img_function) {
      $_[0] = &$img_function($_[0]);
    }
    return $_[0];
  }
}

sub creole_img {
  return unless defined $_[0];
  $img_function = $_[0];
}

sub creole_tag {
  my ($tag, $type, $text) = @_;
  if(! $tag) {
    foreach (sort keys %chunks) {
      my $o = $chunks{$_}{open};
      my $c = $chunks{$_}{close};
      next unless $o && $o =~ /</so;
      $o =~ s/\n/\\n/gso if $o; $o = "" unless $o;
      $c =~ s/\n/\\n/gso if $c; $c = "" unless $c;
      print "$_: open($o) close($c)\n";
    }
  } else {
    return unless ($type eq "open" || $type eq "close");
    return unless $chunks{$tag};
    $chunks{$tag}{$type} = $text ? $text : "";
  }
}

1;
__END__


=head1 NAME

Text::WikiCreole - Convert Wiki Creole 1.0 markup to XHTML

=head1 VERSION

Version 0.07

=head1 DESCRIPTION

Text::WikiCreole implements the Wiki Creole markup language, 
version 1.0, as described at http://www.wikicreole.org.  It
reads Creole 1.0 markup and returns XHTML.

=head1 SYNOPSIS

 use Text::WikiCreole;
 creole_plugin \&myplugin; # register custom plugin parser

 my $html = creole_parse($creole_text);
 ...

=head1 FUNCTIONS

=head2 creole_parse

    Self-explanatory.  Takes a Creole markup string argument and 
    returns HTML. 

=head2 creole_plugin

    Creole 1.0 supports two plugin syntaxes: << plugin content >> and
                                            <<< plugin content >>>

    Write a function that receives the text between the <<>> 
    delimiters as $_[0] (and not including the delimiters) and 
    returns the text to be displayed.  For example, here is a 
    simple plugin that converts plugin text to uppercase:

    sub uppercase_plugin {
      $_[0] =~ s/([a-z])/\u$1/gs;
      return $_[0];
    }
    creole_plugin \&uppercase_plugin;

    If you do not register a plugin function, plugin markup will be left
    as is, including the surrounding << >>.

=head2 creole_link

    You may wish to customize [[ links ]], such as to prefix a hostname,
    port, etc.

    Write a function, similar to the plugin function, which receives the
    URL part of the link (with leading and trailing whitespace stripped) 
    as $_[0] and returns the customized link.  For example, to prepend 
    "http://my.domain/" to pagename:

    sub mylink {
      return "http://my.domain/$_[0]";
    }
    creole_link \&mylink;

=head2 creole_customlinks

    If you want complete control over links, rather than just modifying
    the URL, register your link markup function with creole_link() as above
    and then call creole_customlinks().  Now your function will receive the 
    entire link markup chunk, such as [[ some_wiki_page | page description ]] 
    and must return HTML.
  
    This has no effect on "bare" link markup, such as http://cpan.org.

=head2 creole_barelink

    Same purpose as creole_link, but for "bare" link markup.

    sub mybarelink {
      return "$_[0].html";
    }
    creole_barelink \&mybarelink;

=head2 creole_custombarelinks

    Same purpose as creole_customlinks, but for "bare" link markup.

=head2 creole_img

    Same purpose as creole_link, but for image URLs.

    sub myimg {
      return "http://my.comain/$_[0]";
    }
    creole_img \&myimg;

=head2 creole_customimgs

    Similar to creole_customlinks, but for images.

=head2 creole_tag

    You may wish to customize the opening and/or closing tags
    for the various bits of Creole markup.  For example, to
    assign a CSS class to list items:
 
    creole_tag("li", "open", "<li class=myclass>");

    Or to see all current tags:

    print creole_tag();

    The tags that may be of interest are:

    br          dd          dl
    dt          em          h1
    h2          h3          h4
    h5          h6          hr 
    ilink       img         inowiki
    ip          li          link
    mono        nowiki      ol
    p           strong      sub
    sup         table       td
    th          tr          u
    ul

    Those should be self-explanatory, except for inowiki (inline nowiki),
    ilink (bare links, e.g. http://www.cpan.org), and ip (indented paragraph).

=head1 OFFICIAL MARKUP
 
    Here is a summary of the official Creole 1.0 markup 
    elements.  See http://www.wikicreole.org for the full
    details.

    Headings:
    = heading 1       ->    <h1>heading 1</h1>
    == heading 2      ->    <h2>heading 2</h2>
    ...
    ====== heading 6  ->    <h6>heading 6</h6>
   
    Various inline markup:
    ** bold **        ->    <strong> bold </strong>
    // italics //     ->    <em> italics </em>
    **// both //**    ->    <strong><em> both </em></strong>
    [[ link ]]        ->    <a href="link">link</a>
    [[ link | text ]] ->    <a href="link">text</a>
    http://cpan.org   ->    <a href="http://cpan.org">http://cpan.org</a>
    line \\ break     ->    line <br /> break
    {{img.jpg|alt}}   ->    <img src="img.jpg" alt="alt">

    Lists:
    * unordered list        <ul><li>unordered list</li>
    * second item               <li>second item</li>
    ## nested ordered  ->       <ol><li>nested ordered</li>
    *** uber-nested                 <ul><li>uber-nested</li></ul>
    * back to level 1           </ol><li>back to level 1</li></ul>

    Tables:
    |= h1 |= h2       ->    <table><tr><th>h1</th><th>h2</th></tr>
    |  c1 |  c2             <tr><td>c1</td><td>c2</td></tr></table>

    Nowiki (Preformatted):
    {{{                     <pre>
      ** not bold **          ** not bold **
      escaped HTML:   ->      escaped HTML:
      <i> test </i>           &lt;i&gt; test &lt;/i&gt;
    }}}                     <pre>

    {{{ inline\\also }}} -> <tt>inline\\also</tt>

    Escape Character:
    ~** not bold **    ->    ** not bold **
    tilde: ~~          ->    tilde: ~

    Paragraphs are separated by other blocks and blank lines.  
    Inline markup can usually be combined, overlapped, etc.  List
    items and plugin text can span lines.

=head1 EXTENDED MARKUP

    In addition to OFFICIAL MARKUP, Text::WikiCreole also supports
    the following markup:

    Plugins:
    << plugin >>        ->    whatever you want (see creole_plugin above)
    <<< plugin >>>      ->    whatever you want (see creole_plugin above)
        Triple-bracket syntax has priority, in order to allow you to embed
        double-brackets in plugins, such as to embed Perl code.

    Inline:
    ## monospace ##     ->    <tt> monospace </tt>
    ^^ superscript ^^   ->    <sup> superscript </sup>
    ,, subscript ,,     ->    <sub> subscript </sub>
    __ underline __     ->    <u> underline </u>
    (TM)                ->    &trade;
    (R)                 ->    &reg;
    (C)                 ->    &copy;
    ...                 ->    &hellip;
    --                  ->    &ndash;

    Indented Paragraphs:
    :this               ->    <div style="margin-left:2em"><p>this
    is indented               is indented</p>
    :: more indented          <div style="margin-left:2em"><p> more
                              indented</div></div>

    Definition Lists:
    ; Title             ->    <dl><dt>Title</dt>
    : item 1 : item 2         <dd>item 1</dd><dd>item 2</dd>
    ; Title 2 : item2a        <dt>Title 2</dt><dd>item 2a</dd></dl>

=head1 AUTHOR

Jason Burnett, C<< <jason at jnj.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-text-wikicreole at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Text-WikiCreole>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Text::WikiCreole

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Text-WikiCreole>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Text-WikiCreole>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Text-WikiCreole>

=item * Search CPAN

L<http://search.cpan.org/dist/Text-WikiCreole>

=back

=head1 ACKNOWLEDGEMENTS

The parsing algorithm is basically the same as (and inspired by)
the one in Document::Parser.  Document::Parser is OO and is, 
as such, incompatible with my brain.

=head1 COPYRIGHT & LICENSE

Copyright 2007 Jason Burnett, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

