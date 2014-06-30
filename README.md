a10-dram-tools
===========

This is a set of tools, which can assist in configuring the Allwinner
A10/A13/A20 DRAM controller. A modified version of the a10-meminfo tool
from https://github.com/maxnet/a10-meminfo (originally implemented by
Floris Bos) is also included.

Installation instructions:

    git clone https://github.com/ssvb/a10-dram-tools.git
    cd a10-dram-tools
    cmake -DCMAKE_INSTALL_PREFIX=/usr .
    make -j2 install

Usage instructions: http://linux-sunxi.org/A10_DRAM_Controller_Calibration
