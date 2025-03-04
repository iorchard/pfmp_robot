pfmp_robot
==========

This is a robot automation program to set up Dell PFMP.

Pre-requisite
--------------

Install the prerequisite packages.::

   # for debian-base distro
   $ sudo apt update 
   $ sudo apt -y install qemu-system-x86 qemu-utils \
      libvirt-clients libvirt-daemon-system libguestfs-tools
   
   # for rhel-based distro
   $ sudo dnf -y install qemu-kvm qemu-img libivrt libguestfs-tools

(rhel-based distro) Enable and start libvirtd service.::

   $ sudo systemctl enable --now libvirtd.service

(debian-based distro) Set the setuid of qemu-bridge-helper.::

   $ sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper

Install
--------

Create a python virtual env.::

    $ python3 -m venv ~/.envs/pfmp
    $ source ~/.envs/pfmp/bin/activate
    (pfmp) $ pip install wheel
    (pfmp) $ pip install robotframework

Edit props.py until "# Do not edit below this line!!!".

Run
-----

To set up VMs::

    (pfmp) $ pfmp -d output setup.pfmp
    (pfmp) $ unset USERPW

Tear Down
----------

To tear down VMs.::

    (pfmp) $ robot -d output teardown.robot

It will stop VMs and delete VM images.
