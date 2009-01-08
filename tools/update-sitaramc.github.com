#!/bin/bash

die() { echo "$@"; exit 1; }

export outdir=../sitaramc.github.com
echo >&2
echo WARNING: if you **removed** any files, clear $outdir manually first >&2
echo >&2

cd $outdir || die "couldnt CD to $outdir"
git reset --hard really_empty || die "couldnt reset to really_empty"
cd -

find . -name "*.notes" |sort |while read r
do
    echo $r >&2
    d=$(dirname $r)
    b=$(basename $r .notes)
    mkdir -p              $outdir/$d
    wiki_creole.pl < $r > $outdir/$d/$b.html
    [[ $oldd == $d ]] || {
        [[ -n $oldd ]] && echo "</ul>"
        echo "<strong>$d</strong>:<br />"
        echo "<ul>"
    }
    echo "<li><a href=\"$d/$b.html\">"
    echo "    " $(head -1 < $d/$b.notes | cut -c3-)
    echo "    " "</a></li>"

    oldd=$d
done > $outdir/index.html
echo ...git notes done >&2

wiki_creole.pl < gittalk.notes | tools/mkslidy.pl > $outdir/gittalk.html
mkdir -p $outdir/tools
cp tools/git.png $outdir/tools
cp tools/slidy.* $outdir/tools
echo ...git talk done >&2

cd ~/hobbits/info/notes
./.mk.notes *.notes
cd -
mv ~-/notes.html $outdir
echo ...main notes done >&2

cd $outdir || die "couldnt CD to $outdir"
cat > README <<EOF

Forking this repo

    Don't!

    This will get blown away (reset) every time.  Fork "git-notes" instead.

Why?

    Because I really, **really** like indentation (just one level, no more) of
    normal text compared to headers (as in this file).  I'm really big on this
    -- I can't stand to have **everything** flush left.  But both textile and
    markdown require that all normal text should be left indented.

    For this and other reasons, I *much* prefer WikiCreole.  Anyway, it's not
    a big deal to do the conversion offline and push the HTML into its own
    repo, so that's what I do.

WikiCreole?  What's that?

    Read the README.notes inside the "git-notes" repo for more details about
    my markup.

EOF
git add .
git commit -m "latest HTML output (see git-notes repo for history)"
echo now you can:
echo '    ' cd $outdir\; git push -f\; cd -
