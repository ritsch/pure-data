#! /bin/sh
#
# Creates standalone Windows application directory from Pd build.
#
# Make sure Pd has been configured and built
# before running this.
#

# stop on error
set -e

TK=
prototype_tk=true
build_tk=false

# include sources
sources=false

# strip binaries
strip=true
STRIP=${STRIP-strip}
STRIPARGS=${STRIPARGS-"--strip-unneeded -R .note -R .comment"}

# build dir, relative to working directory
custom_builddir=false
BUILD=..

# Help message
#----------------------------------------------------------
help() {
echo -e "
Usage: msw-app.sh [OPTIONS] [VERSION]

  Creates a Pd app directory for Windows.

  Uses the included Tk 8.5 in pdprototype.tgz by default

Options:
  -h,--help           display this help message

  -t,--tk VER or DIR  use a specific precompiled Tcl/Tk directory or download
                      and build a specific version using tcltk-build.sh

  -s,--sources        include source files in addition to headers
                      (default: ${sources})

  -n,--no-strip       do not strip binaries (default: do strip)

  --builddir <DIR>    set Pd build directory path (default: ${BUILD})

Arguments:

  VERSION             optional string to use in dir name ie. pd-VERSION

Examples:

    # create pd directory
    msw-app.sh

    # create pd-0.48-1 directory, uses specified version string
    msw-app.sh 0.48-1

    # create pd directory with source files
    msw-app.sh --sources

    # create pd-0.48-1 directory, download and build Tcl/Tk 8.5.19
    msw-app.sh --tk 8.5.19 0.48-1

    # create pd-0.48-1 directory, use Tcl/Tk 8.5.19 built with tcltk-dir.sh
    msw-app.sh --tk tcltk-8.5.19 0.48-1
"
}

# Parse command line arguments
#----------------------------------------------------------
while [ "$1" != "" ] ; do
    case $1 in
        -t|--tk)
            if [ $# = 0 ] ; then
                echo "-t,--tk option requires a VER or DIR argument"
                exit 1
            fi
            shift 1
            TK="$1"
            prototype_tk=false
            ;;
        -s|--sources)
            sources=false
            ;;
        -n|--no-strip)
            strip=false
            ;;
        --builddir)
            if [ $# = 0 ] ; then
                echo "--builddir option requires a DIR argument"
                exit 1
            fi
            shift 1
            BUILD=${1%/} # remove trailing slash
            custom_builddir=true
            ;;
        -s|--sources)
            sources=true
            ;;
        -h|--help)
            help
            exit 0
            ;;
        *)
            break ;;
    esac
    shift 1
done

# check for version argument and set app path in the dir the script is run from
if [ "x$1" != "x" ] ; then
    APP=$(pwd)/pd-$1
else
    # version not specified
    APP=$(pwd)/pd
fi

# Go
#----------------------------------------------------------

# make sure custom build directory is an absolute path
if [ "x$custom_builddir" = "xtrue" ] ; then
    if [ "x${BUILD#/}" = "x${BUILD}" ] ; then
        # BUILD isn't absolute as it doesn't start with '/'
        BUILD="$(pwd)/$BUILD"
    fi
fi

# is $TK a version or a directory?
if [ -d "$TK" ] ; then
    # directory, make sure it's absolute
    if [ "x${TK#/}" = "x${TK}" ] ; then
        TK="$(pwd)/$TK"
    fi
else
    # version, so it will be downloaded & built
    build_tk=true
fi

# change to the dir of this script
cd $(dirname $0)

echo "==== Creating $(basename $APP)"

# remove old app dir if found
if [ -d $APP ] ; then
    echo "removing exiting directory"
    rm -rf $APP
fi

# install to app directory
make -C $BUILD install DESTDIR=$APP prefix=/

# don't need man pages
rm -rf $APP/share

# place headers together in src directory
mv $APP/include $APP/src
mv $APP/src/pd/* $APP/src
rm -rf $APP/src/pd

# move folders from lib/pd into top level directory
rm -rf $APP/lib/pd/bin
for d in $APP/lib/pd/*; do
    mv $d $APP/
done
rm -rf $APP/lib/

# install sources
if [ "x$sources" = xtrue ] ; then
    mkdir -p $APP/src
    cp -v ../src/*.c $APP/src/
    cp -v ../src/*.h $APP/src/
    for d in $APP/extra/*/; do
        s=${d%/}
        s=../extra/${s##*/}
        cp -v "${s}"/*.c "${d}"
    done
fi

# untar pdprototype.tgz
tar -xf pdprototype.tgz -C $APP/ --strip-components=1
if [ "x$prototype_tk" = xfalse ] ; then

    # remove bundled tcl & tk as we'll install our own,
    # keep dlls needed by pd & externals
    rm -rf $APP/bin/tcl* $APP/bin/tk* \
           $APP/bin/wish*.exe $APP/bin/tclsh*.exe \
           $APP/lib

    # build, if needed
    if [ "x$build_tk" = xtrue ] ; then
         echo "Building tcltk-$TK"
        ./tcltk-dir.sh $TK
        TK=tcltk-${TK}
    else
        echo "Using $TK"
    fi

    # install tcl & tk
    cp -R $TK/bin $APP/
    cp -R $TK/lib $APP/
fi

# install info
cp -v ../README.txt  $APP/
cp -v ../LICENSE.txt $APP/

# strip executables,
# use temp files as stripping in place doesn't seem to work reliable on Windows
if [ "x$strip" = xtrue ] ; then
    find "${APP}" -type f '(' -iname "*.exe" -o -iname "*.com" -o -iname "*.dll" ')' \
    | while read file ; do \
        "${STRIP}" ${STRIPARGS} -o "$file.stripped" "$file" && \
        mv "$file.stripped" "$file" && \
        echo "stripped $file" ; \
    done
fi

# set permissions and clean up
find $APP -type f -exec chmod -x {} +
find $APP -type f '(' -iname "*.exe" -o -iname "*.com" ')' -exec chmod +x {} +
find $APP -type f '(' -iname "*.la" -o -iname "*.dll.a" -o -iname "*.am" ')' -delete
find $APP/bin -type f -not -name "*.*" -delete

# finished
touch $APP
echo  "==== Finished $(basename $APP)"
