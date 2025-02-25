--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Ada_2022;

with System.Storage_Elements;

with A0B.ARMv7M.NVIC_Utilities;
with A0B.STM32F401.GPIO.PIOA;
with A0B.STM32F401.SVD.RCC;
with A0B.STM32F401.USB_Lines;
with A0B.Types;

package body A0B.USB.Controllers.STM32F401_OTG_FS is

   procedure Initialize_Core (Self : in out OTG_FS_Device_Controller'Class);

   procedure Initialize_Device (Self : in out OTG_FS_Device_Controller'Class);

   procedure EP_Initialization_On_USB_Reset
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure EP_Initialization_On_Enumeration_Completion
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_RXFLVL (Self : in out OTG_FS_Device_Controller'Class);

   ------------
   -- Enable --
   ------------

   procedure Enable (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      null;
   end Enable;

   -------------------------------------------------
   -- EP_Initialization_On_Enumeration_Completion --
   -------------------------------------------------

   procedure EP_Initialization_On_Enumeration_Completion
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      use type A0B.Types.Unsigned_2;

   begin
      --  [RM0368] 22.17.5 Device programming model
      --
      --  Endpoint initialization on enumeration completion

      --  1. On the Enumeration Done interrupt (ENUMDNE in OTG_FS_GINTSTS),
      --  read the OTG_FS_DSTS register to determine the enumeration speed.

      if Self.Device_Peripheral.FS_DSTS.ENUMSPD /= 2#11# then
         raise Program_Error;
      end if;

      --  2. Program the MPSIZ field in OTG_FS_DIEPCTL0 to set the maximum
      --  packet size. This step configures control endpoint 0. The maximum
      --  packet size for a control endpoint depends on the enumeration speed.

      Self.Device_Peripheral.FS_DIEPCTL0.MPSIZ := 0;  --  00: 64 bytes
   end EP_Initialization_On_Enumeration_Completion;

   ------------------------------------
   -- EP_Initialization_On_USB_Reset --
   ------------------------------------

   procedure EP_Initialization_On_USB_Reset
     (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      --  [RM0368] 22.17.5 Device programming model
      --
      --  Endpoint initialization on USB reset

      --  1. Set the NAK bit for all OUT endpoints
      --    – SNAK = 1 in OTG_FS_DOEPCTLx (for all OUT endpoints)

      Self.Device_Peripheral.DOEPCTL0.SNAK := True;
      Self.Device_Peripheral.DOEPCTL1.SNAK := True;
      Self.Device_Peripheral.DOEPCTL2.SNAK := True;
      Self.Device_Peripheral.DOEPCTL3.SNAK := True;

      --  2. Unmask the following interrupt bits
      --    – INEP0 = 1 in OTG_FS_DAINTMSK (control 0 IN endpoint)
      --    – OUTEP0 = 1 in OTG_FS_DAINTMSK (control 0 OUT endpoint)
      --    – STUP = 1 in DOEPMSK
      --    – XFRC = 1 in DOEPMSK
      --    – XFRC = 1 in DIEPMSK
      --    – TOC = 1 in DIEPMSK

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINTMSK_Register :=
           Self.Device_Peripheral.FS_DAINTMSK;

      begin
         Aux.IEPM := 2#0001#;
         --  INEP0 = 1 in OTG_FS_DAINTMSK (control 0 IN endpoint)
         Aux.OEPINT := 2#0001#;
         --  OUTEP0 = 1 in OTG_FS_DAINTMSK (control 0 OUT endpoint)

         --  XXX What about other endpoints?

         Self.Device_Peripheral.FS_DAINTMSK := Aux;
      end;

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DOEPMSK_Register :=
           Self.Device_Peripheral.FS_DOEPMSK;

      begin
         Aux.XFRCM := True;  --  1: Unmasked interrupt
         --  Aux.EPDM  := XXX
         Aux.STUPM := True;  --  1: Unmasked interrupt
         --  Aux.OTEPDM := XXX
         --  Aux. STSPHSRXM:  --  XXX not in SVD
         --  Aux.OUTPKTERRM:  --  XXX not in SVD
         --  Aux.BERRM:  --  XXX not in SVD
         --  Aux.NAKMSK:  --  XXX not in SVD

         Self.Device_Peripheral.FS_DOEPMSK := Aux;
      end;

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DIEPMSK_Register :=
           Self.Device_Peripheral.FS_DIEPMSK;

      begin
         Aux.XFRCM := True;  --  1: Unmasked interrupt
         --  Aux.EPDM  := XXX
         Aux.TOM   := True;  --  1: Unmasked interrupt
         --  Aux.ITTXFEMSK := XXX
         --  Aux.INEPNMM := XXX
         --  Aux.INEPNEM := XXX
         --  Aux.NAKM := XXX not in SVD

         Self.Device_Peripheral.FS_DIEPMSK := Aux;
      end;

      Self.Global_Peripheral.FS_GRXFSIZ.RXFD := 256;

      Self.Device_Peripheral.DOEPTSIZ0.STUPCNT := 3;
   end EP_Initialization_On_USB_Reset;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      A0B.STM32F401.GPIO.PIOA.PA11.Configure_Alternative_Function
        (A0B.STM32F401.USB_Lines.OTG_FS_DM);
      A0B.STM32F401.GPIO.PIOA.PA12.Configure_Alternative_Function
        (A0B.STM32F401.USB_Lines.OTG_FS_DP);

      A0B.STM32F401.SVD.RCC.RCC_Periph.AHB2ENR.OTGFSEN := True;
      --  Enable clock of USB peripheral. `Q` diveder is set by startup code.

      Self.Initialize_Core;
      Self.Initialize_Device;

      Self.Global_Peripheral.FS_GINTMSK.RXFLVLM := True;
      --  XXX it is unclear when it should be enabled, enable it here.

      A0B.ARMv7M.NVIC_Utilities.Enable_Interrupt (A0B.STM32F401.OTG_FS);
      A0B.ARMv7M.NVIC_Utilities.Enable_Interrupt
        (A0B.STM32F401.EXTI18_OTG_FS_Wakeup);
   end Initialize;

   ---------------------
   -- Initialize_Core --
   ---------------------

   procedure Initialize_Core (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      --  [RM0368] 22.17.1 Core Initialization

      --  1. Program the following fields in the OTG_FS_GAHBCFG register:
      --    – Global interrupt mask bit GINTMSK = 1
      --    – RxFIFO non-empty (RXFLVL bit in OTG_FS_GINTSTS)
      --    – Periodic TxFIFO empty level

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_GAHBCFG_Register :=
           Self.Global_Peripheral.FS_GAHBCFG;

      begin
         Aux.GINT    := True;
         --  1: Unmask the interrupt assertion to the application.
         Aux.TXFELVL := True;
         --  1: the TXFE (in OTG_FS_DIEPINTx) interrupt indicates that the IN
         --  Endpoint TxFIFO is completely empty
         --  Aux.PTXFELVL := <>;  --  Only in host mode

         Self.Global_Peripheral.FS_GAHBCFG := Aux;
      end;

      --  2. Program the following fields in the OTG_FS_GUSBCFG register:
      --    – HNP capable bit
      --    – SRP capable bit
      --    – FS timeout calibration field
      --    – USB turnaround time field

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_GUSBCFG_Register :=
           Self.Global_Peripheral.FS_GUSBCFG;

      begin
         Aux.TOCAL  := 7;      --  XXX It is unclear what to set here
         --  Aux.PHYSEL := <>;  This bit is always 1 with read-only access.
         Aux.SRPCAP := False;  --  0: SRP capability is not enabled.
         Aux.HNPCAP := False;  --  0: HNP capability is not enabled.
         Aux.TRDT   := 6;      --  Table 133, for AHB @84MHz
         Aux.FHMOD  := False;  --  0: Normal mode
         Aux.FDMOD  := True;   --  1: Force device mode
         Aux.CTXPKT := False;  --  Never set this bit to 1.

         Self.Global_Peripheral.FS_GUSBCFG := Aux;

         --  After change of FDMOD/FHMOD the application must wait at least 25
         --  ms before the change takes effect.
         --
         --  XXX Not implemented yet!
      end;

      --  3. The software must unmask the following bits in the OTG_FS_GINTMSK
      --  register:
      --    – OTG interrupt mask
      --    – Mode mismatch interrupt mask

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTMSK_Register :=
           Self.Global_Peripheral.FS_GINTMSK;

      begin
      --  --  Start of frame mask
      --  SOFM             : Boolean := False;
      --  --  Receive FIFO non-empty mask
      --  RXFLVLM          : Boolean := False;
      --  --  Non-periodic TxFIFO empty mask
      --  NPTXFEM          : Boolean := False;
      --  --  Global non-periodic IN NAK effective mask
      --  GINAKEFFM        : Boolean := False;
      --  --  Global OUT NAK effective mask
      --  GONAKEFFM        : Boolean := False;
      --  --  unspecified
      --  Reserved_8_9     : A0B.Types.SVD.UInt2 := 16#0#;
      --  --  Early suspend mask
      --  ESUSPM           : Boolean := False;
      --  --  USB suspend mask
      --  USBSUSPM         : Boolean := False;
      --  --  USB reset mask
      --  USBRST           : Boolean := False;
      --  --  Enumeration done mask
      --  ENUMDNEM         : Boolean := False;
      --  --  Isochronous OUT packet dropped interrupt mask
      --  ISOODRPM         : Boolean := False;
      --  --  End of periodic frame interrupt mask
      --  EOPFM            : Boolean := False;
      --  --  unspecified
      --  Reserved_16_16   : A0B.Types.SVD.Bit := 16#0#;
      --  --  Endpoint mismatch interrupt mask
      --  EPMISM           : Boolean := False;
      --  --  IN endpoints interrupt mask
      --  IEPINT           : Boolean := False;
      --  --  OUT endpoints interrupt mask
      --  OEPINT           : Boolean := False;
      --  --  Incomplete isochronous IN transfer mask
      --  IISOIXFRM        : Boolean := False;
      --  --  Incomplete periodic transfer mask(Host mode)/Incomplete isochronous
      --  --  OUT transfer mask(Device mode)
      --  IPXFRM_IISOOXFRM : Boolean := False;
      --  --  unspecified
      --  Reserved_22_23   : A0B.Types.SVD.UInt2 := 16#0#;
      --  --  Read-only. Host port interrupt mask
      --  PRTIM            : Boolean := False;
      --  --  Host channels interrupt mask
      --  HCIM             : Boolean := False;
      --  --  Periodic TxFIFO empty mask
      --  PTXFEM           : Boolean := False;
      --  --  unspecified
      --  Reserved_27_27   : A0B.Types.SVD.Bit := 16#0#;
      --  --  Connector ID status change mask
      --  CIDSCHGM         : Boolean := False;
      --  --  Disconnect detected interrupt mask
      --  DISCINT          : Boolean := False;
      --  --  Session request/new session detected interrupt mask
      --  SRQIM            : Boolean := False;
      --  --  Resume/remote wakeup detected interrupt mask
      --  WUIM             : Boolean := False;

         Aux.MMISM  := True;  --  1: Unmasked interrupt
         Aux.OTGINT := True;  --  1: Unmasked interrupt

         Self.Global_Peripheral.FS_GINTMSK := Aux;
      end;
   end Initialize_Core;

   -----------------------
   -- Initialize_Device --
   -----------------------

   procedure Initialize_Device (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      --  [RM0368] 22.17.1 Core Initialization

      --  1. Program the following fields in the OTG_FS_DCFG register:
      --    – Device speed
      --    – Non-zero-length status OUT handshake

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DCFG_Register :=
           Self.Device_Peripheral.FS_DCFG;

      begin
      --  --  Device address
      --  DAD            : FS_DCFG_DAD_Field := 16#0#;
      --  --  Periodic frame interval
      --  PFIVL          : FS_DCFG_PFIVL_Field := 16#0#;

         Aux.DSPD     := 2#11#;
         --  11: Full speed (USB 1.1 transceiver clock is 48 MHz)
         Aux.NZLSOHSK := True;
         --  1: Send a STALL handshake on a nonzero-length status OUT
         --  transaction and do not send the received OUT packet to the
         --  application.
         --  XXX Should it be configurable?
         --  Aux.DAD      := XXX Set later?
         --  Aux.PFIVL    := <>;  Not used yet

         Self.Device_Peripheral.FS_DCFG := Aux;
      end;

      --  2. Program the OTG_FS_GINTMSK register to unmask the following
      --  interrupts:
      --    – USB reset
      --    – Enumeration done
      --    – Early suspend
      --    – USB suspend
      --    – SOF

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTMSK_Register :=
           Self.Global_Peripheral.FS_GINTMSK;

      begin
      --  --  Start of frame mask
      --  SOFM             : Boolean := False;
      --  --  Receive FIFO non-empty mask
      --  RXFLVLM          : Boolean := False;
      --  --  Non-periodic TxFIFO empty mask
      --  NPTXFEM          : Boolean := False;
      --  --  Global non-periodic IN NAK effective mask
      --  GINAKEFFM        : Boolean := False;
      --  --  Global OUT NAK effective mask
      --  GONAKEFFM        : Boolean := False;
      --  --  unspecified
      --  Reserved_8_9     : A0B.Types.SVD.UInt2 := 16#0#;
      --  --  Early suspend mask
      --  ESUSPM           : Boolean := False;
      --  --  USB suspend mask
      --  USBSUSPM         : Boolean := False;
      --  --  USB reset mask
      --  USBRST           : Boolean := False;
      --  --  Enumeration done mask
      --  ENUMDNEM         : Boolean := False;
      --  --  Isochronous OUT packet dropped interrupt mask
      --  ISOODRPM         : Boolean := False;
      --  --  End of periodic frame interrupt mask
      --  EOPFM            : Boolean := False;
      --  --  unspecified
      --  Reserved_16_16   : A0B.Types.SVD.Bit := 16#0#;
      --  --  Endpoint mismatch interrupt mask
      --  EPMISM           : Boolean := False;
      --  --  IN endpoints interrupt mask
      --  IEPINT           : Boolean := False;
      --  --  OUT endpoints interrupt mask
      --  OEPINT           : Boolean := False;
      --  --  Incomplete isochronous IN transfer mask
      --  IISOIXFRM        : Boolean := False;
      --  --  Incomplete periodic transfer mask(Host mode)/Incomplete isochronous
      --  --  OUT transfer mask(Device mode)
      --  IPXFRM_IISOOXFRM : Boolean := False;
      --  --  unspecified
      --  Reserved_22_23   : A0B.Types.SVD.UInt2 := 16#0#;
      --  --  Read-only. Host port interrupt mask
      --  PRTIM            : Boolean := False;
      --  --  Host channels interrupt mask
      --  HCIM             : Boolean := False;
      --  --  Periodic TxFIFO empty mask
      --  PTXFEM           : Boolean := False;
      --  --  unspecified
      --  Reserved_27_27   : A0B.Types.SVD.Bit := 16#0#;
      --  --  Connector ID status change mask
      --  CIDSCHGM         : Boolean := False;
      --  --  Disconnect detected interrupt mask
      --  DISCINT          : Boolean := False;
      --  --  Session request/new session detected interrupt mask
      --  SRQIM            : Boolean := False;
      --  --  Resume/remote wakeup detected interrupt mask
      --  WUIM             : Boolean := False;

         Aux.SOFM     := True;  --  1: Unmasked interrupt
         Aux.ESUSPM   := True;  --  1: Unmasked interrupt
         Aux.USBSUSPM := True;  --  1: Unmasked interrupt
         Aux.USBRST   := True;  --  1: Unmasked interrupt
         Aux.ENUMDNEM := True;  --  1: Unmasked interrupt

         Self.Global_Peripheral.FS_GINTMSK := Aux;
      end;

      --  3. Program the VBUSBSEN bit in the OTG_FS_GCCFG register to enable
      --  VBUS sensing in “B” device mode and supply the 5 volts across
      --  the pull-up resistor on the DP line.

      declare
         use type A0B.Types.Unsigned_11;

         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_GCCFG_Register :=
           Self.Global_Peripheral.FS_GCCFG;

      begin
      --  --  Power down
      --  PWRDWN         : Boolean := False;
      --  --  unspecified
      --  Reserved_17_17 : A0B.Types.SVD.Bit := 16#0#;
      --  --  Enable the VBUS sensing device
      --  VBUSASEN       : Boolean := False;
      --  --  Enable the VBUS sensing device
      --  VBUSBSEN       : Boolean := False;
      --  --  SOF output enable
      --  SOFOUTEN       : Boolean := False;
      --  --  unspecified
      --  Reserved_21_31 : A0B.Types.SVD.UInt11 := 16#0#;

         Aux.PWRDWN   := True;
         --  1: Power down deactivated (“Transceiver active”)
         Aux.VBUSASEN := False;  --  0: VBUS sensing “A” disabled
         Aux.VBUSBSEN := False;  --  0: VBUS sensing “B” disabled
         Aux.SOFOUTEN := False;
         --  0: SOF pulse not available on PAD (OTG_FS_SOF)
         Aux.Reserved_21_31 := @ or 1;
         --  1: VBUS sensing not available by hardware.

         Self.Global_Peripheral.FS_GCCFG := Aux;
      end;
   end Initialize_Device;

   ------------------
   -- On_Interrupt --
   ------------------

   Reset : Boolean := False;

   procedure On_Interrupt (Self : in out OTG_FS_Device_Controller'Class) is
      Status : constant A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register :=
        Self.Global_Peripheral.FS_GINTSTS;
      Done   : Boolean := False;

      --  XXX default values for some components are 1, status cleanup code
      --  must be fixed.

   begin
      if Status.MMIS then
         Self.Global_Peripheral.FS_GINTSTS := (MMIS => True, others => <>);

         raise Program_Error;
      end if;

      if Status.OTGINT then
         raise Program_Error;
      end if;

      if Status.SOF then
         Self.Global_Peripheral.FS_GINTSTS := (SOF => True, others => <>);

         Done := True;
         --  raise Program_Error;
      end if;

      if Status.RXFLVL then
         Self.On_RXFLVL;

         Done := True;
      end if;

      if Status.ESUSP then
         Self.Global_Peripheral.FS_GINTSTS := (ESUSP => True, others => <>);

         return;
         --  raise Program_Error;
      end if;

      if Status.USBSUSP then
         Self.Global_Peripheral.FS_GINTSTS := (USBSUSP => True, others => <>);

         return;
         --  raise Program_Error;
      end if;

      if Status.USBRST then
         Self.Global_Peripheral.FS_GINTSTS := (USBRST => True, others => <>);

         if Reset then
            raise Program_Error;

         else
            Reset := True;
         end if;

         Self.EP_Initialization_On_USB_Reset;
         Done := True;
      end if;

      if Status.ENUMDNE then
         Self.Global_Peripheral.FS_GINTSTS.ENUMDNE := True;

         Self.EP_Initialization_On_Enumeration_Completion;
         Done := True;
      end if;

      if not Done then
         raise Program_Error;
      end if;
   end On_Interrupt;

   ---------------
   -- On_RXFLVL --
   ---------------

   type Setup_Buffer is array (0 .. 7) of A0B.Types.Unsigned_8 with Pack;

   Buffer     : Setup_Buffer;
   Setup      : Boolean := False;
   Setup_Done : Boolean := False;
   SUPCNT     : Integer := Integer'Last;

   procedure On_RXFLVL
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      use type A0B.Types.Unsigned_2;
      use type A0B.Types.Unsigned_4;
      use type A0B.Types.Unsigned_11;
      use type System.Storage_Elements.Storage_Offset;

      GRXSTSRP_Device :
        A0B.STM32F401.SVD.USB_OTG_FS.FS_GRXSTSR_Device_Register
          with Import,
               Address =>
                (Self.Global_Peripheral.FS_GRXSTSR_Device'Address + 4);

      Status : A0B.STM32F401.SVD.USB_OTG_FS.FS_GRXSTSR_Device_Register :=
        GRXSTSRP_Device;

   begin
      if Status.PKTSTS = 2#0110#  --  Setup data packet received
        and Status.BCNT = 8
        and Status.EPNUM = 0
        and Status.DPID = 2#00#   --  DATA0
      then
         if Setup then
            raise Program_Error;

         else
            Setup := True;
         end if;

         SUPCNT := Integer (Self.Device_Peripheral.DOEPTSIZ0.STUPCNT);

         declare
            FIFO : A0B.Types.Unsigned_32
              with Import,
                Volatile, Full_Access_Only,
              Address => System.Storage_Elements.To_Address (16#5000_1000#);
            --  FIFO : Setup_Buffer with Import,
            --    Address => System.Storage_Elements.To_Address (16#5000_1000#);
            B    : array (0 .. 1) of A0B.Types.Unsigned_32
              with Import, Address => Buffer'Address;

         begin
            --  Buffer := FIFO;
            B(0) := FIFO;
            B(1) := FIFO;
            --  B(2) := FIFO;

            --  Status := GRXSTSRP_Device;
            --  raise Program_Error;
         end;

      elsif Status.PKTSTS = 2#0100#   --  SETUP transaction completed
        and Status.BCNT = 0
        and Status.EPNUM = 0
        and Status.DPID = 2#00#  --  Don't care, not need to be tested
      then
         if Setup_Done then
            raise Program_Error;
         end if;

         Setup_Done := True;

         Status := GRXSTSRP_Device;

      else

         raise Program_Error;
      end if;
   end On_RXFLVL;

end A0B.USB.Controllers.STM32F401_OTG_FS;
