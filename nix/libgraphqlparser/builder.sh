source $stdenv/setup

PATH=$cmake/bin:$PATH
PATH=$python2/bin:$PATH

echo $PATH

cmake -S $src -DCMAKE_INSTALL_PREFIX:PATH=$out .
make
make install #prefix=$out
