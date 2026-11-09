# Using Makefile
Last edited 11/4/2026 by Patchy

This file goes over the setup to use the Makefile in rtl/wishbone

## Install Fusesoc
~~~
module load 
module load python3/3.11
python3 -m pip install --user fusesoc
~~~

## Load Questa
~~~ 
module av     # List all available modules
module load <put a questa version here>
~~~

## Load Cores into FuseSoc Library
~~~ 
cd rtl/wishbone
fusesoc library add / .
fusesoc core list
~~~ 