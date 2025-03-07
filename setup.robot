*** Settings ***
Documentation    Build VM for a lab.
Suite Setup      Preflight
Library         OperatingSystem
Library         Process
Library         String
Variables       props.py

*** Variables ***
${VM_MAN}       ${CURDIR}/scripts/vm_man.sh
${MACGEN}       ${CURDIR}/scripts/macgen.sh

*** Tasks ***
Set Up Lab
    [Documentation]     Set up virtual machines.
    [Tags]    takeoff
    Run     echo "127.0.0.1 localhost"|sudo tee data/hosts
    Log     \n      console=True
    FOR     ${vm}   IN  @{VMS}
        Log        ${vm}: Add VM IP in /etc/hosts.    console=True
        ${rc} =        Run And Return Rc
        ...    grep -q "${IPS['${vm}']['${MGMT_BR}']['ip']}.*${vm}" /etc/hosts
        Run Keyword If    ${rc} != 0        Run 
        ...        echo "${IPS['${vm}']['${MGMT_BR}']['ip']} ${vm} # ${OS}"|sudo tee -a /etc/hosts
        Run     echo "${IPS['${vm}']['${MGMT_BR}']['ip']} ${vm} # ${OS}"|sudo tee -a data/hosts
    END

    FOR     ${vm}   IN  @{VMS}
        ${vm_exists} =    Check If VM Exists    ${vm}
        IF    ${vm_exists}
          Log    VM ${vm} exists so skip creating it.    console=True
          CONTINUE
        END
        
        ${imgfile} =    Set Variable If    'installer' in ${ROLES['${vm}']}
        ...    ${INSTALLER_IMG}
        ...    ${IMG}
        Log  Copy ${SRC_DIR}/${imgfile} to ${DST_DIR}/${vm}.qcow2  console=True
        Copy File   ${SRC_DIR}/${imgfile}   ${DST_DIR}/${vm}.qcow2

        Log        Resize the image to ${DISK}[${vm}]G.    console=True
        ${rc} =     Run And Return Rc
        ...     qemu-img resize ${DST_DIR}/${vm}.qcow2 ${DISK}[${vm}]G
        Should Be Equal As Integers     ${rc}   0

        Log        Resize root partition to 100%.        console=True
        ${rc} =     Run And Return Rc
        ...     virt-resize --expand /dev/sda1 ${SRC_DIR}/${imgfile} ${DST_DIR}/${vm}.qcow2
        Should Be Equal As Integers     ${rc}   0

        ${rc}   ${uuid} =   Run And Return Rc And Output
        ...     cat /proc/sys/kernel/random/uuid

        Log     Create XML for ${vm}    console=True
        Create XML  ${vm}   ${uuid}    default.tpl

        Log     Define VM     console=True
        ${rc} =     Wait Until Keyword Succeeds		3x	1s
        ...     Run And Return Rc    virsh define ${TEMPDIR}/xml
        Should Be Equal As Integers     ${rc}   0

        Log     Attach disk for ${vm}    console=True
        Attach Disk     ${vm}

        Log     Attach interfaces to ${vm}        console=True
        Create Interfaces        ${vm}  ${IPS}[${vm}]

        Log     Run ${VM_MAN}       console=True
        ${rc}   ${out} =     Run And Return Rc And Output
        ...     ${VM_MAN} -f ${DST_DIR}/${vm}.qcow2 -u ${USERID}
        Should Be Equal As Integers     ${rc}   0   
        ...     msg="vm_man failed: ${out}"
    END

Start Lab
    [Documentation]     Start virtual machines. 
    [Tags]    flying
    Log     \n      console=True
    FOR     ${vm}   IN  @{VMS}
        ${vm_state} =    Check VM State    ${vm}
        IF    "${vm_state}" == "shut off"
            Log     Start ${vm}     console=True
            ${rc} =     Run And Return Rc     virsh start ${vm}
            Should Be Equal As Integers     ${rc}   0
        END
    END

*** Keywords ***
Preflight
    Comment     Run before Tasks.
    Directory Should Exist    ${SRC_DIR}
    File Should Exist    ${SRC_DIR}/${IMG}
    Create Directory    ${DST_DIR}
    Log        Create ${SSHKEY} if not exists        console=True
    ${rc} =        Run And Return Rc    ls ${SSHKEY}
    Run Keyword If    ${rc} != 0        
    ...        Run        ssh-keygen -t rsa -N '' -f ${SSHKEY}

Create XML
    [Documentation]     Create XML.
    [Arguments]     ${vm}   ${uuid}     ${tpl}
    ${rc} =     Run And Return Rc
    ...     sed -e 's/NAME/${vm}/;s/UUID/${uuid}/;s/MEM/${MEM}[${vm}]/;s/CORES/${CORES}[${vm}]/' data/${tpl} > ${TEMPDIR}/xml
    Should Be Equal As Integers     ${rc}   0

Attach Disk
    [Arguments]     ${vm}
    Run     virsh attach-disk ${vm} ${DST_DIR}/${vm}.qcow2 sda --driver qemu --subdriver qcow2 --targetbus scsi --persistent

Create Interfaces
    [Documentation]        Create Interfaces
    [Arguments]        ${vm}    ${ifaces}
    ${i} =        Set Variable    0
    Remove File     ${TEMPDIR}/ifcfg*
    FOR     ${br}   IN         @{ifaces}
        Log        ${vm}:${br}:${ifaces['${br}']}        console=True
        ${netinfo} =    Set Variable    ${ifaces['${br}']}

        ${rc}   ${mac} =    Run And Return Rc And Output    ${MACGEN}
        Should Be Equal As Integers     ${rc}   0

        Run     virsh attach-interface --domain ${vm} --type bridge --source ${br} --model virtio --mac ${mac} --persistent

        Run Keyword If    "${netinfo['ip']}" == ""
        ...         Create File     ${TEMPDIR}/ifcfg-eth${i}
        ...         NAME=eth${i}\nDEVICE=eth${i}\nHWADDR=${mac}\nIPV6_DISABLED=yes\nONBOOT=yes
        ...     ELSE IF     'gw' in ${netinfo}
        ...         Create File     ${TEMPDIR}/ifcfg-eth${i}
        ...         NAME=eth${i}\nDEVICE=eth${i}\nHWADDR=${mac}\nGATEWAY=${netinfo['gw']}\nIPADDR=${netinfo['ip']}\nPREFIX=${netinfo['nm']}\nIPV6_DISABLED=yes\nONBOOT=yes
        ...     ELSE
        ...         Create File     ${TEMPDIR}/ifcfg-eth${i}
        ...         NAME=eth${i}\nDEVICE=eth${i}\nHWADDR=${mac}\nIPADDR=${netinfo['ip']}\nPREFIX=${netinfo['nm']}\nIPV6_DISABLED=yes\nONBOOT=yes
        ${i} =        Evaluate    ${i} + 1
    END

Check If VM Exists
    [Documentation]        Create Interfaces
    [Arguments]        ${vm}
    Log  Skip VM provision if ${DST_DIR}/${vm}.qcow2 exists  console=True
    ${vm_exists} =    Run Keyword And Return Status
    ...    File Should Exist  ${DST_DIR}/${vm}.qcow2
    RETURN    ${vm_exists}

Check VM State
    [Arguments]     ${v}
    ${rc}   ${o} =      Run And Return Rc And Output    
    ...     LANG=C virsh domstate ${v}
    ${out} =    Remove String    ${o}    \n
    RETURN    ${out}
