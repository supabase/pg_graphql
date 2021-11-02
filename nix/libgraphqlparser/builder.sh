source $stdenv/setup

tar xvfz $src

PATH=$cmake/bin:$PATH
PATH=$python2/bin:$PATH

echo $PATH

cd $name
cmake -DCMAKE_INSTALL_PREFIX:PATH=$out .
make
make install #prefix=$out
