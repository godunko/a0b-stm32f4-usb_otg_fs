--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Ada_2022;

with Ada.Unchecked_Conversion;
with System.Storage_Elements;

--  with A0B.ARMv7M.SCS.DWT;
with A0B.ARMv7M.Profiling_Utilities;
with A0B.ARMv7M.NVIC_Utilities;
with A0B.STM32F401.GPIO.PIOA;
with A0B.STM32F401.SVD.RCC;
with A0B.STM32F401.USB_Lines;
with A0B.Types;
with A0B.USB.Endpoints.Control;

package body A0B.USB.Controllers.STM32F401_OTG_FS is

   EP0_FIFO_Address : constant System.Address :=
     System.Storage_Elements.To_Address (16#5000_1000#);
   EP1_FIFO_Address : constant System.Address :=
     System.Storage_Elements.To_Address (16#5000_2000#);
   --  EP2_FIFO_Address : constant System.Address :=
   --    System.Storage_Elements.To_Address (16#5000_3000#);
   --  EP3_FIFO_Address : constant System.Address :=
   --    System.Storage_Elements.To_Address (16#5000_4000#);

   procedure Initialize_Core (Self : in out OTG_FS_Device_Controller'Class);

   procedure Initialize_Device (Self : in out OTG_FS_Device_Controller'Class);

   procedure Internal_Set_Address
     (Self    : in out OTG_FS_Device_Controller'Class;
      Address : Address_Field_Type);

   procedure EP_Initialization_On_USB_Reset
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure EP_Initialization_On_Enumeration_Completion
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_Enumeration_Done (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_In_Endpoint_Interrupt
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_Out_Endpoint_Interrupt
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_RXFLVL (Self : in out OTG_FS_Device_Controller'Class);

   procedure On_USB_Reset (Self : in out OTG_FS_Device_Controller'Class);

   procedure Initiate_IN0_Stall
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure Initiate_IN0_Acknowledge
     (Self : in out OTG_FS_Device_Controller'Class);

   procedure Initiate_IN0_Transfer
     (Self   : in out OTG_FS_Device_Controller'Class;
      Buffer : System.Address;
      Size   : A0B.Types.Unsigned_16);

   procedure Initiate_IN1_Transfer
     (Self   : in out OTG_FS_Device_Controller'Class);
      --  Buffer : System.Address;
      --  Size   : A0B.Types.Unsigned_16);

   procedure Read_FIFO (Self : in out OTG_FS_Device_Controller'Class);
   --  Copy data from FIFO into OUT buffer.
   --
   --  Implementation reads FIFO by words, split individual bytes and stores
   --  them separately. Thus, data can use any alignment.

   procedure Write_FIFO
     (Self           : in out OTG_FS_Device_Controller'Class;
      FIFO_Address   : System.Address;
      Buffer_Address : System.Address;
      Length         : A0B.Types.Unsigned_32);
   --  Copy data from IN buffer into FIFO.
   --
   --  Implementation reads data from the memory as bytes, construct words and
   --  writes them to FIFO. Thus, data can use any alignment.

   function Active_Interrupts
     (Self : OTG_FS_Device_Controller'Class)
      return A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register;
   --  Retuns active not masked interrups

   type FIX_DIEPINT_Register is record
      --  XFRC
      XFRC           : Boolean := False;
      --  EPDISD
      EPDISD         : Boolean := False;
      --  unspecified
      Reserved_2_2   : A0B.Types.Reserved_1  := A0B.Types.Zero;
      --  TOC
      TOC            : Boolean := False;
      --  ITTXFE
      ITTXFE         : Boolean := False;
      --  INEPNM
      INEPNM         : A0B.Types.Reserved_1  := A0B.Types.Zero;
      --  INEPNE
      INEPNE         : Boolean := False;
      --  Read-only. TXFE
      TXFE           : Boolean := False;
      --  unspecified
      Reserved_8_10  : A0B.Types.Reserved_3  := A0B.Types.Zero;
      --  PKTDRPSTS
      PKTDRPSTS      : Boolean := False;
      --  unspecified
      Reserved_12_12 : A0B.Types.Reserved_1  := A0B.Types.Zero;
      --  NAK
      NAK            : Boolean               := False;
      Reserved_14_31 : A0B.Types.Reserved_18 := A0B.Types.Zero;
   end record
     with Object_Size => 32, Bit_Order => System.Low_Order_First;

   for FIX_DIEPINT_Register use record
      XFRC           at 0 range 0 .. 0;
      EPDISD         at 0 range 1 .. 1;
      Reserved_2_2   at 0 range 2 .. 2;
      TOC            at 0 range 3 .. 3;
      ITTXFE         at 0 range 4 .. 4;
      INEPNM         at 0 range 5 .. 5;
      INEPNE         at 0 range 6 .. 6;
      TXFE           at 0 range 7 .. 7;
      Reserved_8_10  at 0 range 8 .. 10;
      PKTDRPSTS      at 0 range 11 .. 11;
      Reserved_12_12 at 0 range 12 .. 12;
      NAK            at 0 range 13 .. 13;
      Reserved_14_31 at 0 range 14 .. 31;
   end record;

   package Logger is

      procedure Interrupt
        (GINTSTS : A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register);

      procedure RXFLVL
        (GRXSTSR : A0B.STM32F401.SVD.USB_OTG_FS.FS_GRXSTSR_Device_Register);

      procedure IEP_Interrupt
        (IEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_IEPINT_Field);

      procedure IEP0_Interrupt
        (DIEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register);

      procedure IEP1_Interrupt
        (DIEPINT1 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register);

      procedure OEP_Interrupt
        (OEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_OEPINT_Field);

      procedure OEP0_Interrupt
        (DOEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register);

      procedure OEP2_Interrupt
        (DOEPINT2 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register);

      procedure Setup_Data
        (Data : A0B.USB.Endpoints.Control.Setup_Data_Buffer);

      procedure Transmit_IN1;

   end Logger;

   package body Logger is

      type Event_Kind is
        (None,
         Interrupt,
         RXFLVL,
         IEP_Interrupt,
         IEP0_Interrupt,
         IEP1_Interrupt,
         OEP_Interrupt,
         OEP0_Interrupt,
         OEP2_Interrupt,
         Setup_Data,
         Transmit_IN1);

      type Event_Record (Kind : Event_Kind := None) is record
         Stamp : A0B.ARMv7M.Profiling_Utilities.Stamp;

         case Kind is
            when None =>
               null;

            when Interrupt =>
               GINTSTS : A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register;

            when RXFLVL =>
               GRXSTSR : A0B.STM32F401.SVD.USB_OTG_FS.FS_GRXSTSR_Device_Register;

            when OEP_Interrupt =>
               OEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_OEPINT_Field;

            when IEP_Interrupt =>
               IEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_IEPINT_Field;

            when IEP0_Interrupt =>
               DIEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register;

            when IEP1_Interrupt =>
               DIEPINT1 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register;
               DIEPCTL1 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPCTL1_Register;

            when OEP0_Interrupt =>
               DOEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register;

            when OEP2_Interrupt =>
               DOEPINT2 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register;

            when Setup_Data =>
               Data : A0B.USB.Endpoints.Control.Setup_Data_Buffer;

            when Transmit_IN1 =>
               null;
         end case;
      end record;

      Log  : array (1 .. 400) of Event_Record;
      Last : Natural := 0;

      procedure Append (Item : Event_Record);

      function Stamp return A0B.ARMv7M.Profiling_Utilities.Stamp;

      ------------
      -- Append --
      ------------

      procedure Append (Item : Event_Record) is
      begin
         Last := @ + 1;
         Log (Last) := Item;
      end Append;

      --------------------
      -- IEP0_Interrupt --
      --------------------

      procedure IEP0_Interrupt
        (DIEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register) is
      begin
         Append ((IEP0_Interrupt, Stamp, DIEPINT0));
      end IEP0_Interrupt;

      --------------------
      -- IEP1_Interrupt --
      --------------------

      procedure IEP1_Interrupt
        (DIEPINT1 : A0B.STM32F401.SVD.USB_OTG_FS.DIEPINT_Register) is
      begin
         Append
           ((IEP1_Interrupt, Stamp, DIEPINT1, A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Periph.DIEPCTL1));
      end IEP1_Interrupt;

      -------------------
      -- IEP_Interrupt --
      -------------------

      procedure IEP_Interrupt
        (IEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_IEPINT_Field) is
      begin
         Append ((IEP_Interrupt, Stamp, IEPINT));
      end IEP_Interrupt;

      ---------------
      -- Interrupt --
      ---------------

      procedure Interrupt
        (GINTSTS : A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register) is
      begin
         Append ((Interrupt, A0B.ARMv7M.Profiling_Utilities.Get, GINTSTS));
      end Interrupt;

      --------------------
      -- OEP0_Interrupt --
      --------------------

      procedure OEP0_Interrupt
        (DOEPINT0 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register) is
      begin
         Append ((OEP0_Interrupt, Stamp, DOEPINT0));
      end OEP0_Interrupt;

      --------------------
      -- OEP2_Interrupt --
      --------------------

      procedure OEP2_Interrupt
        (DOEPINT2 : A0B.STM32F401.SVD.USB_OTG_FS.DOEPINT_Register) is
      begin
         Append ((OEP2_Interrupt, Stamp, DOEPINT2));
      end OEP2_Interrupt;

      -------------------
      -- OEP_Interrupt --
      -------------------

      procedure OEP_Interrupt
        (OEPINT : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_OEPINT_Field) is
      begin
         Append ((OEP_Interrupt, Stamp, OEPINT));
      end OEP_Interrupt;

      ------------
      -- RXFLVL --
      ------------

      procedure RXFLVL
        (GRXSTSR : A0B.STM32F401.SVD.USB_OTG_FS.FS_GRXSTSR_Device_Register) is
      begin
         Append ((RXFLVL, Stamp, GRXSTSR));
      end RXFLVL;

      ----------------
      -- Setup_Data --
      ----------------

      procedure Setup_Data
        (Data : A0B.USB.Endpoints.Control.Setup_Data_Buffer) is
      begin
         Append ((Setup_Data, Stamp, Data));
      end Setup_Data;

      -----------
      -- Stamp --
      -----------

      function Stamp return A0B.ARMv7M.Profiling_Utilities.Stamp is
      begin
         return A0B.ARMv7M.Profiling_Utilities.Get;
      end Stamp;

      ------------------
      -- Transmit_IN1 --
      ------------------

      procedure Transmit_IN1 is
      begin
         Append ((Transmit_IN1, Stamp));
      end Transmit_IN1;

   end Logger;

   B_Cycles : Natural := 0 with Export;
   P_Cycles : Natural := 0 with Export;
   X_Cycles : Natural := 0 with Export;

   -----------------------
   -- Active_Interrupts --
   -----------------------

   function Active_Interrupts
     (Self : OTG_FS_Device_Controller'Class)
      return A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register
   is
      use type A0B.Types.Unsigned_32;

      function As_GINTSTS is
        new Ada.Unchecked_Conversion
             (A0B.Types.Unsigned_32,
              A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register);

      State : A0B.Types.Unsigned_32
        with Import, Address => Self.Global_Peripheral.FS_GINTSTS'Address;
      Mask  : A0B.Types.Unsigned_32
        with Import, Address => Self.Global_Peripheral.FS_GINTMSK'Address;

   begin
      return As_GINTSTS (State and Mask);
   end Active_Interrupts;

   -----------
   -- Do_IN --
   -----------

   --  overriding procedure Do_IN
   --    (Self : in out OTG_FS_Device_Controller;
   --     Data : A0B.Types.Arrays.Unsigned_8_Array)
   --  is
   --     --  use type A0B.Types.Unsigned_2;
   --     --  use type A0B.Types.Unsigned_7;
   --
   --  begin
   --     Self.Device_Peripheral.DIEPTSIZ0 := (others => <>);
   --     Self.Device_Peripheral.DIEPTSIZ0 :=
   --       (XFRSIZ => 18, PKTCNT => 1, others => <>);
   --       --  (XFRSIZ => 18, PKTCNT => 3, others => <>);
   --       --  (XFRSIZ => 0, PKTCNT => 1, others => <>);
   --
   --     declare
   --        Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DIEPCTL0_Register :=
   --          Self.Device_Peripheral.FS_DIEPCTL0;
   --
   --     begin
   --        Aux.CNAK := True;
   --        Aux.EPENA := True;
   --
   --        Self.Device_Peripheral.FS_DIEPCTL0 := Aux;
   --     end;
   --
   --     --  declare
   --     --        FIFO : A0B.Types.Unsigned_32
   --     --          with Import,
   --     --            Volatile, Full_Access_Only,
   --     --          Address => System.Storage_Elements.To_Address (16#5000_1000#);
   --     --        B    : array (0 .. 4) of A0B.Types.Unsigned_32
   --     --          with Import, Address => Data'Address;
   --     --
   --     --  begin
   --     --     FIFO := B (0);
   --     --     FIFO := B (1);
   --     --     FIFO := B (2);
   --     --     FIFO := B (3);
   --     --     FIFO := B (4);
   --     --  end;
   --
   --     --  while Self.Device_Peripheral.DIEPTSIZ0.XFRSIZ /= 0 loop
   --     --     B_Cycles := @ + 1;
   --     --  end loop;
   --     --
   --     --  while Self.Device_Peripheral.DIEPTSIZ0.PKTCNT /= 0 loop
   --     --     P_Cycles := @ + 1;
   --     --     null;
   --     --  end loop;
   --
   --     --  while not Self.Device_Peripheral.DIEPINT0.XFRC loop
   --     --     X_Cycles := @ + 1;
   --     --     null;
   --     --  end loop;
   --     --
   --     --  Self.Device_Peripheral.DOEPCTL0.CNAK := True;
   --     --  Self.Device_Peripheral.DOEPCTL0.EPENA := True;
   --     --  Self.Device_Peripheral.DOEPTSIZ0.PKTCNT := True;
   --
   --     Self.IN_Buffer := Data'Address;
   --     Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := 2#0001#;
   --
   --     raise Program_Error;
   --  end Do_IN;

   -----------------------
   -- Configuration_Set --
   -----------------------

   overriding procedure Configuration_Set
     (Self : in out OTG_FS_Device_Controller) is
   begin
      --  This section describes what the application must do when it receives
      --  a SetConfiguration or SetInterface command in a SETUP packet.
      --
      --  1.When a SetConfiguration command is received, the application
      --  must program the endpoint registers to configure them with the
      --  characteristics of the valid endpoints in the new configuration.
      --
      --  2.When a SetInterface command is received, the application must
      --  program the endpoint registers of the endpoints affected by this
      --  command.
      --
      --  3.Some endpoints that were active in the prior configuration or
      --  alternate setting are not valid in the new configuration or
      --  alternate setting. These invalid endpoints must be deactivated.
      --
      --  4.Unmask the interrupt for each active endpoint and mask the
      --  interrupts for all inactive endpoints in the OTG_FS_DAINTMSK
      --  register.
      --
      --  5.Set up the Data FIFO RAM for each FIFO.
      --
      --  6.After all required endpoints are configured; the application must
      --  program the core to send a status IN packet.
      --
      --  At this point, the device core is configured to receive and transmit
      --  any type of data packet.

      --  Endpoint 1:

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DIEPCTL1_Register :=
           Self.Device_Peripheral.DIEPCTL1;

      begin
         Aux.MPSIZ          := 64;
         Aux.USBAEP         := True;
         --  EONUM_DPID  --  Read-only
         --  NAKSTS      --  Read-only
         Aux.EPTYP          := 2#10#;   --  10: Bulk
         Aux.Stall          := False;
         Aux.TXFNUM         := 16#01#;  --  TxFIFO 1
         --  Aux.CNAK           := True;    --  Clear NAK
         --  Aux.SNAK           := False;
         Aux.CNAK           := False;
         Aux.SNAK           := True;     --  Set NAK
         Aux.SD0PID_SEVNFRM := False;
         Aux.SODDFRM_SD1PID := False;
         Aux.EPDIS          := False;   --  '0' has no effect on the bit value
         Aux.EPENA          := False;   --  '0' has no effect on the bit value

         Self.Device_Peripheral.DIEPCTL1 := Aux;
      end;

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DOEPCTL_Register :=
           Self.Device_Peripheral.DOEPCTL1;

      begin
         Aux.MPSIZ          := 64;
         Aux.USBAEP         := True;
         --  EONUM_DPID  --  Read-only
         --  NAKSTS      --  Read-only
         Aux.EPTYP          := 2#10#;  --  10: Bulk
         Aux.SNPM           := False;  --  Snoop mode disabled
         Aux.Stall          := False;
         Aux.CNAK           := True;   --  Clear NAK
         Aux.SNAK           := False;
         Aux.SD0PID_SEVNFRM := False;
         Aux.SODDFRM        := False;
         Aux.EPDIS          := False;  --  '0' has no effect on the bit value
         Aux.EPENA          := False;  --  '0' has no effect on the bit value
         --  Aux.EPENA          := True;

         Self.Device_Peripheral.DOEPCTL1 := Aux;
      end;

      declare
         use type A0B.Types.Unsigned_16;

         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINTMSK_Register :=
           Self.Device_Peripheral.FS_DAINTMSK;

      begin
         Aux.IEPM   := @ or 2#0010#;
         Aux.OEPINT := @ or 2#0010#;

         Self.Device_Peripheral.FS_DAINTMSK := Aux;
      end;

      --  Endpoint 2:

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DIEPCTL_Register :=
           Self.Device_Peripheral.DIEPCTL2;

      begin
         Aux.MPSIZ          := 64;
         Aux.USBAEP         := True;
         --  EONUM_DPID  --  Read-only
         --  NAKSTS      --  Read-only
         Aux.EPTYP          := 2#10#;   --  10: Bulk
         Aux.Stall          := False;
         Aux.TXFNUM         := 16#02#;  --  TxFIFO 2
         Aux.CNAK           := True;    --  Clear NAK
         Aux.SNAK           := False;
         Aux.SD0PID_SEVNFRM := False;
         Aux.SODDFRM        := False;
         Aux.EPDIS          := False;   --  '0' has no effect on the bit value
         Aux.EPENA          := False;   --  '0' has no effect on the bit value

         Self.Device_Peripheral.DIEPCTL2 := Aux;
      end;

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DOEPCTL_Register :=
           Self.Device_Peripheral.DOEPCTL2;

      begin
         Aux.MPSIZ          := 64;
         Aux.USBAEP         := True;
         --  EONUM_DPID  --  Read-only
         --  NAKSTS      --  Read-only
         Aux.EPTYP          := 2#10#;  --  10: Bulk
         Aux.SNPM           := False;  --  Snoop mode disabled
         Aux.Stall          := False;
         Aux.CNAK           := True;   --  Clear NAK
         Aux.SNAK           := False;
         Aux.SD0PID_SEVNFRM := False;
         Aux.SODDFRM        := False;
         Aux.EPDIS          := False;  --  '0' has no effect on the bit value
         Aux.EPENA          := False;  --  '0' has no effect on the bit value

         Self.Device_Peripheral.DOEPCTL2 := Aux;
      end;

      declare
         use type A0B.Types.Unsigned_16;

         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINTMSK_Register :=
           Self.Device_Peripheral.FS_DAINTMSK;

      begin
         Aux.IEPM   := @ or 2#0100#;
         Aux.OEPINT := @ or 2#0100#;

         Self.Device_Peripheral.FS_DAINTMSK := Aux;
      end;
   end Configuration_Set;

   ------------
   -- Enable --
   ------------

   procedure Enable (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      null;
   end Enable;

   --------------
   -- EP1_Send --
   --------------

   --  overriding procedure EP1_Send
   --    (Self   : in out OTG_FS_Device_Controller;
   --     Buffer : System.Address;
   --     Size   : A0B.Types.Unsigned_16) is
   --  begin
   --     Self.Initiate_IN1_Transfer (Buffer, Size);
   --  end EP1_Send;

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
      --  Self.Device_Peripheral.FS_DIEPCTL0.MPSIZ := 2#11#;  --  11: 8 bytes
      --  Self.Device_Peripheral.FS_DIEPCTL0.SNAK := True;   --  XXX  ???
      Self.Device_Peripheral.FS_DIEPCTL0.CNAK := True;   --  XXX  ???

      Self.Device_Peripheral.DOEPTSIZ0.XFRSIZ  := 64;
      Self.Device_Peripheral.DOEPTSIZ0.PKTCNT  := True;
      Self.Device_Peripheral.DOEPTSIZ0.STUPCNT := 3;
   end EP_Initialization_On_Enumeration_Completion;

   ------------------------------------
   -- EP_Initialization_On_USB_Reset --
   ------------------------------------

   procedure EP_Initialization_On_USB_Reset
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      --  use type A0B.Types.Unsigned_16;
      --
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

      Self.Global_Peripheral.FS_GINTMSK.IEPINT := True;
      Self.Global_Peripheral.FS_GINTMSK.OEPINT := True;

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

         Aux.EPDM  := True;
         Aux.INEPNMM   := True;
         Aux.INEPNEM   := True;

         --  XXX ITTXFE is generated when host requests IN packet, but it is
         --  not available yet (one of the case is that TX FIFO is not filled
         --  by necessary amount of data). It might be useful to detect cases
         --  when processing take too long time, but generally, it is expected
         --  and handled by USB protocol/controller without any actions from
         --  the application.
         --
         --  XXX NAK is disabled too. Yet.
         --
         --  Aux.ITTXFEMSK := True;
         --  Aux.Reserved_7_31 := 2#1000000#;  --  Aux.NAKM := XXX not in SVD


         Self.Device_Peripheral.FS_DIEPMSK := Aux;
      end;

      --  3. Set up the Data FIFO RAM for each of the FIFOs
      --
      --    – Program the OTG_FS_GRXFSIZ register, to be able to receive
      --  control OUT data and setup data. If thresholding is not enabled, at a
      --  minimum, this must be equal to 1 max packet size of control endpoint
      --  0 + 2 words (for the status of the control OUT data packet) + 10
      --  words (for setup packets).
      --
      --    – Program the OTG_FS_TX0FSIZ register (depending on the FIFO number
      --  chosen) to be able to transmit control IN data. At a minimum, this
      --  must be equal to 1 max packet size of control endpoint 0.

      --  Size of RX FIFO is
      --    512 bytes for OUT2 enpoint packet
      --     64 bytes for control enpoint packet
      --      2 words for the status of the control OUT data packet
      --     10 words for setup packets
      --    ---
      --    156 words (624 bytes)
      --
      --  Size of TX0 FIFO is 16 words (64 bytes)
      --
      --  Size of TX1 FIFO is 128 words (512 bytes)
      --
      --  Size of TX2 FIFO is 16 words (64 bytes)
      --
      --  Total amount is 1_264 bytes (of 1_280 bytes)

      declare
         RX_Size    : constant := 156;
         FX0_Offset : constant := RX_Size;
         FX0_Size   : constant := 16;
         FX1_Offset : constant := FX0_Offset + FX0_Size;
         FX1_Size   : constant := 128;
         FX2_Offset : constant := FX1_Offset + FX1_Size;
         FX2_Size   : constant := 16;

      begin
         Self.Global_Peripheral.FS_GRXFSIZ.RXFD := RX_Size;
         Self.Global_Peripheral.FS_GNPTXFSIZ_Device :=
           (TX0FSA => FX0_Offset, TX0FD => FX0_Size);
         Self.Global_Peripheral.FS_DIEPTXF1 :=
           (INEPTXSA => FX1_Offset, INEPTXFD => FX1_Size);
         Self.Global_Peripheral.FS_DIEPTXF2 :=
           (INEPTXSA => FX2_Offset, INEPTXFD => FX2_Size);
      end;
   end EP_Initialization_On_USB_Reset;

   ------------------
   -- Get_Endpoint --
   ------------------

   overriding function Get_Endpoint
     (Self     : in out OTG_FS_Device_Controller;
      Endpoint : A0B.USB.Endpoint_Number)
      return not null access A0B.USB.Endpoints.Abstract_Endpoint'Class is
   begin
      case Endpoint is
         when 1      => return Self.EP1'Unchecked_Access;
         when 2      => return Self.EP2'Unchecked_Access;
         when 3      => return Self.EP3'Unchecked_Access;
         when others => raise Program_Error;
      end case;
   end Get_Endpoint;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      A0B.ARMv7M.Profiling_Utilities.Initialize;

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
      --  --  Periodic frame interval
      --  PFIVL          : FS_DCFG_PFIVL_Field := 16#0#;

         Aux.DSPD     := 2#11#;
         --  11: Full speed (USB 1.1 transceiver clock is 48 MHz)
         Aux.NZLSOHSK := False;
         --  0: Send the received OUT packet to the application (zero-length
         --  or nonzero-length) and send a handshake based on the NAK and STALL
         --  bits for the endpoint in the Device endpoint control register.
         Aux.DAD      := 0;  --  Initial device address

         --  Aux.NZLSOHSK := True;
         --  1: Send a STALL handshake on a nonzero-length status OUT
         --  transaction and do not send the received OUT packet to the
         --  application.
         --  XXX Should it be configurable?
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

         --  Aux.SOFM     := True;  --  1: Unmasked interrupt
         --  Aux.ESUSPM   := True;  --  1: Unmasked interrupt
         --  Aux.USBSUSPM := True;  --  1: Unmasked interrupt
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

   ------------------------------
   -- Initiate_IN0_Acknowledge --
   ------------------------------

   procedure Initiate_IN0_Acknowledge
     (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      Self.Device_Peripheral.DIEPTSIZ0 :=
        (XFRSIZ => 0, PKTCNT => 0, others => <>);

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DIEPCTL0_Register :=
           Self.Device_Peripheral.FS_DIEPCTL0;

      begin
         Aux.CNAK  := True;
         Aux.EPENA := True;

         Self.Device_Peripheral.FS_DIEPCTL0 := Aux;
      end;
   end Initiate_IN0_Acknowledge;

   ------------------------
   -- Initiate_IN0_Stall --
   ------------------------

   procedure Initiate_IN0_Stall
     (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DIEPCTL0_Register :=
           Self.Device_Peripheral.FS_DIEPCTL0;

      begin
         Aux.STALL := True;
         Aux.EPENA := False;
         Aux.EPDIS := True;

         Self.Device_Peripheral.FS_DIEPCTL0 := Aux;
      end;
   end Initiate_IN0_Stall;

   ---------------------------
   -- Initiate_IN0_Transfer --
   ---------------------------

   procedure Initiate_IN0_Transfer
     (Self   : in out OTG_FS_Device_Controller'Class;
      Buffer : System.Address;
      Size   : A0B.Types.Unsigned_16)
   is
      use type A0B.Types.Unsigned_16;

      --  FIFO : aliased A0B.Types.Unsigned_32
      --    with Import,
      --         Volatile,
      --         Full_Access_Only,
      --         Address => System.Storage_Elements.To_Address (16#5000_1000#);

      Packet_Size  : constant A0B.Types.Unsigned_16 :=
        A0B.Types.Shift_Left
          (64, Integer (Self.Device_Peripheral.FS_DIEPCTL0.MPSIZ));
      Packet_Count : constant A0B.Types.Unsigned_16 :=
        (Size + Packet_Size - 1) / Packet_Size;

   begin
      Self.IN_Buffer := Buffer;
      Self.IN_Size   := Size;

      Self.Device_Peripheral.DIEPTSIZ0 :=
        (XFRSIZ => A0B.STM32F401.SVD.USB_OTG_FS.DIEPTSIZ0_XFRSIZ_Field (Size),
         PKTCNT =>
           A0B.STM32F401.SVD.USB_OTG_FS.DIEPTSIZ0_PKTCNT_Field (Packet_Count),
         others => <>);

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.FS_DIEPCTL0_Register :=
           Self.Device_Peripheral.FS_DIEPCTL0;

      begin
         Aux.CNAK  := True;
         Aux.EPENA := True;

         Self.Device_Peripheral.FS_DIEPCTL0 := Aux;
      end;

      Self.Write_FIFO
        (EP0_FIFO_Address,
         Self.IN_Buffer,
         A0B.Types.Unsigned_32 (Self.IN_Size));

      --  Self.Device_Peripheral.DOEPCTL0.CNAK := True;
      --  Self.Device_Peripheral.DOEPCTL0.EPENA := True;
      --  Self.Device_Peripheral.DOEPTSIZ0.PKTCNT := True;

      --  Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := 2#0001#;
   end Initiate_IN0_Transfer;

   ---------------------------
   -- Initiate_IN1_Transfer --
   ---------------------------

   procedure Initiate_IN1_Transfer
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      use type A0B.Types.Unsigned_32;
      use type A0B.STM32F401.SVD.USB_OTG_FS.DIEPEMPMSK_INEPTXFEM_Field;

      Packet_Size  : constant A0B.Types.Unsigned_32 :=
        A0B.Types.Unsigned_32 (Self.Device_Peripheral.DIEPCTL1.MPSIZ);
      Packet_Count : constant A0B.Types.Unsigned_32 :=
        (Self.EP1.IN_Transfer.Size + Packet_Size - 1) / Packet_Size;

   begin
      Self.Device_Peripheral.DIEPTSIZ1 :=
        (XFRSIZ =>
           A0B.STM32F401.SVD.USB_OTG_FS.DIEPTSIZ_XFRSIZ_Field
             (Self.EP1.IN_Transfer.Size),
         PKTCNT =>
           A0B.STM32F401.SVD.USB_OTG_FS.DIEPTSIZ_PKTCNT_Field (Packet_Count),
         others => <>);

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DIEPCTL1_Register :=
           Self.Device_Peripheral.DIEPCTL1;

      begin
         Aux.CNAK  := True;
         --  Aux.SD0PID_SEVNFRM := True;
         --  Aux.SD0PID_SEVNFRM := False;
         Aux.EPENA := True;

         Self.Device_Peripheral.DIEPCTL1 := Aux;
      end;

      Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := @ or 2#0010#;
   end Initiate_IN1_Transfer;

   --------------------------
   -- Internal_Set_Address --
   --------------------------

   procedure Internal_Set_Address
     (Self    : in out OTG_FS_Device_Controller'Class;
      Address : Address_Field_Type) is
   begin
      Self.Device_Peripheral.FS_DCFG.DAD :=
        A0B.STM32F401.SVD.USB_OTG_FS.FS_DCFG_DAD_Field (Address);
   end Internal_Set_Address;

   -------------------------
   -- On_Enumeration_Done --
   -------------------------

   procedure On_Enumeration_Done (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      Self.EP_Initialization_On_Enumeration_Completion;
   end On_Enumeration_Done;

   ------------------------------
   -- On_In_Endpoint_Interrupt --
   ------------------------------

   procedure On_In_Endpoint_Interrupt
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      use type A0B.Types.Unsigned_16;
      use type A0B.Types.Unsigned_32;
      use type System.Address;

      Status : constant A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_IEPINT_Field :=
        Self.Device_Peripheral.FS_DAINT.IEPINT;

   begin
      Logger.IEP_Interrupt (Status);

      --  XXX Process OTG_FS_DAINT & OTG_FS_DIEPINTx

      if (Status and 2#0001#) /= 0 then
         Logger.IEP0_Interrupt (Self.Device_Peripheral.DIEPINT0);

         --  XXX SVD & documentation doesn't match

         declare
            FIX_DIEPINT0 : FIX_DIEPINT_Register
              with Import, Volatile, Full_Access_Only,
              Address => Self.Device_Peripheral.DIEPINT0'Address;

         begin

         if Self.Device_Peripheral.DIEPINT0.XFRC then
            Self.Device_Peripheral.DIEPINT0 :=
              (XFRC => True, TXFE => False, others => <>);
      --
      Self.Device_Peripheral.DOEPTSIZ0.PKTCNT := True;
      Self.Device_Peripheral.DOEPCTL0.CNAK := True;
      Self.Device_Peripheral.DOEPCTL0.EPENA := True;
            --  raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT0.EPDISD then
            Self.Device_Peripheral.DIEPINT0 :=
              (EPDISD => True, TXFE => False, others => <>);

            --  Endpoint was disabled by application, it is the case when STALL
            --  answer is sent. So, nothing to do.
         end if;

         if Self.Device_Peripheral.DIEPINT0.TOC then
            raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT0.ITTXFE then
            raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT0.INEPNE then
            Self.Device_Peripheral.DIEPINT0 :=
              (INEPNE => True, TXFE => False, others => <>);
            --  raise Program_Error;
            --  XXX ???
         end if;

         if Self.Device_Peripheral.DIEPINT0.TXFE
           and Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM = 1  --  XXX
         then
            --  Read-only. TXFE

            if Self.IN_Buffer = System.Null_Address then
               --  if Sent then
                  --  raise Program_Error;

               --  else
               --     Sent := True;
                  --  Self.Device_Peripheral.FS_DIEPCTL0.CNAK := True;
               --  end if;
               raise Program_Error;
            end if;

            raise Program_Error;
            --  Self.Write_FIFO;
            --
            --  Self.IN_Buffer := System.Null_Address;
            --  Self.IN_Size   := 0;
            --  Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := 2#0000#;
            end if;

            if FIX_DIEPINT0.NAK then
               FIX_DIEPINT0 := (NAK => True, others => <>);
               --  raise Program_Error;
            end if;
         end;
      end if;

      --  EP1

      if (Status and 2#0010#) /= 0 then
         Logger.IEP1_Interrupt (Self.Device_Peripheral.DIEPINT1);

         --  XXX SVD & documentation doesn't match

         declare
            FIX_DIEPINT1 : FIX_DIEPINT_Register
              with Import, Volatile, Full_Access_Only,
              Address => Self.Device_Peripheral.DIEPINT1'Address;

         begin

            if Self.Device_Peripheral.DIEPINT1.XFRC then
               --  XFRC: Transfer completed interrupt

               Self.Device_Peripheral.DIEPINT1 :=
                 (XFRC => True, TXFE => False, others => <>);

               --  XXX Set transfer state and clear endpoint state?

               A0B.Callbacks.Emit_Once (Self.EP1.IN_Callback);
            end if;

         if Self.Device_Peripheral.DIEPINT1.EPDISD then
            Self.Device_Peripheral.DIEPINT1 :=
              (EPDISD => True, TXFE => False, others => <>);

            raise Program_Error;
         end if;

         --  TOC: Applies only to Control IN endpoints.

         if Self.Device_Peripheral.DIEPINT1.TOC then
            Self.Device_Peripheral.DIEPINT1 :=
              (TOC => True, TXFE => False, others => <>);

            raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT1.ITTXFE then
            Self.Device_Peripheral.DIEPINT1 :=
              (ITTXFE => True, TXFE => False, others => <>);

               if not Self.Device_Peripheral.DIEPCTL1.EPENA then
                  raise Program_Error;
               end if;

      declare
         Aux : A0B.STM32F401.SVD.USB_OTG_FS.DIEPCTL1_Register :=
           Self.Device_Peripheral.DIEPCTL1;

      begin
         Aux.CNAK  := True;
         Aux.EPENA := False;

         Self.Device_Peripheral.DIEPCTL1 := Aux;
      end;
         Logger.IEP1_Interrupt (Self.Device_Peripheral.DIEPINT1);

            --  raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT1.INEPNE then
            Self.Device_Peripheral.DIEPINT1 :=
              (INEPNE => True, TXFE => False, others => <>);

            --  raise Program_Error;
         end if;

         if Self.Device_Peripheral.DIEPINT1.TXFE
           and (Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM and 2#0010#) /= 0  --  XXX
         then
            --  --  Read-only. TXFE

            if Self.EP1.IN_Transfer.Size = 0 then
               raise Program_Error;

            else
               Self.Write_FIFO
                 (FIFO_Address   => EP1_FIFO_Address,
                  Buffer_Address => Self.EP1.IN_Transfer.Address,
                  Length         => Self.EP1.IN_Transfer.Size);
               Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := @ and 2#1101#;
            end if;

               --  XXX Why?

            if Self.Device_Peripheral.DIEPINT1.ITTXFE then
               raise Program_Error;
            end if;
            --  --  Self.IN_Buffer := System.Null_Address;
            --  --  Self.IN_Size   := 0;
            --  --  Self.Device_Peripheral.DIEPEMPMSK.INEPTXFEM := 2#0000#;
         end if;

            if FIX_DIEPINT1.NAK then
               FIX_DIEPINT1 := (NAK => True, others => <>);
               Logger.IEP1_Interrupt (Self.Device_Peripheral.DIEPINT1);
               --  raise Program_Error;
            end if;

         end;
      end if;

      if (Status and 2#0100#) /= 0 then
         raise Program_Error;
      end if;

      if (Status and 2#1000#) /= 0 then
         raise Program_Error;
      end if;
   end On_In_Endpoint_Interrupt;

   ------------------
   -- On_Interrupt --
   ------------------

   --  Reset : Boolean := False;

   procedure On_Interrupt (Self : in out OTG_FS_Device_Controller'Class) is
      Status : constant A0B.STM32F401.SVD.USB_OTG_FS.FS_GINTSTS_Register :=
        Self.Active_Interrupts;
   --       Self.Global_Peripheral.FS_GINTSTS;
   --     Done   : Boolean := False;
   --
   --     --  XXX default values for some components are 1, status cleanup code
   --     --  must be fixed.

   begin
      Logger.Interrupt (Status);

      --  WKUPINT            : Boolean := False;

      if Status.MMIS then
         --  Mode mismatch interrupt

         Self.Global_Peripheral.FS_GINTSTS :=
           (MMIS => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.OTGINT then
         --  Read-only. OTG interrupt

         --  XXX Process OTG_FS_GOTGINT

         raise Program_Error;
      end if;

      if Status.SOF then
         --  Start of frame

         Self.Global_Peripheral.FS_GINTSTS :=
           (SOF => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.RXFLVL then
         --  Read-only. RxFIFO non-empty

         Self.On_RXFLVL;
      end if;

      if Status.NPTXFE then
         --  Read-only. Non-periodic TxFIFO empty
         --
         --  Accessible in host mode only.

         raise Program_Error;
      end if;

      if Status.GINAKEFF then
         --  Read-only. Global IN non-periodic NAK effective

         raise Program_Error;
      end if;

      if Status.GOUTNAKEFF then
         --  Read-only. Global OUT NAK effective

         raise Program_Error;
      end if;

      if Status.ESUSP then
         --  Early suspend

         Self.Global_Peripheral.FS_GINTSTS :=
           (ESUSP => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.USBSUSP then
         --  USB suspend

         Self.Global_Peripheral.FS_GINTSTS :=
           (USBSUSP => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.USBRST then
         --  USB reset

         Self.Global_Peripheral.FS_GINTSTS :=
           (USBRST => True, NPTXFE | PTXFE => False, others => <>);

         Self.On_USB_Reset;
      end if;

      if Status.ENUMDNE then
         --  Enumeration done

         Self.Global_Peripheral.FS_GINTSTS :=
           (ENUMDNE => True, NPTXFE | PTXFE => False, others => <>);

         Self.On_Enumeration_Done;
      end if;

      if Status.ISOODRP then
         --  Isochronous OUT packet dropped interrupt

         Self.Global_Peripheral.FS_GINTSTS :=
           (ISOODRP => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.EOPF then
         --  End of periodic frame interrupt

         Self.Global_Peripheral.FS_GINTSTS :=
           (EOPF => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.IEPINT then
         --  Read-only. IN endpoint interrupt

         Self.On_In_Endpoint_Interrupt;
      end if;

      if Status.OEPINT then
         --  Read-only. OUT endpoint interrupt

         Self.On_Out_Endpoint_Interrupt;
      end if;

      if Status.IISOIXFR then
         --  Incomplete isochronous IN transfer

         Self.Global_Peripheral.FS_GINTSTS :=
           (IISOIXFR => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.IPXFR_INCOMPISOOUT then
         --  Incomplete periodic transfer(Host mode)/Incomplete isochronous
         --  OUT transfer(Device mode)

         Self.Global_Peripheral.FS_GINTSTS :=
           (IPXFR_INCOMPISOOUT => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.HPRTINT then
         --  Read-only. Host port interrupt
         --
         --  Only accessible in host mode.

         raise Program_Error;
      end if;

      if Status.HCINT then
         --  Read-only. Host channels interrupt
         --
         --  Only accessible in host mode.

         raise Program_Error;
      end if;

      if Status.PTXFE then
         --  Read-only. Periodic TxFIFO empty
         --
         --  Only accessible in host mode.

         raise Program_Error;
      end if;

      if Status.CIDSCHG then
         --  Connector ID status change

         Self.Global_Peripheral.FS_GINTSTS :=
           (CIDSCHG => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.DISCINT then
         --  Disconnect detected interrupt
         --
         --  Only accessible in host mode.

         Self.Global_Peripheral.FS_GINTSTS :=
           (DISCINT => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.SRQINT then
         --  Session request/new session detected interrupt

         Self.Global_Peripheral.FS_GINTSTS :=
           (SRQINT => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;

      if Status.WKUPINT then
         --  Resume/remote wakeup detected interrupt

         Self.Global_Peripheral.FS_GINTSTS :=
           (WKUPINT => True, NPTXFE | PTXFE => False, others => <>);

         raise Program_Error;
      end if;




   --     if Status.MMIS then
   --        Self.Global_Peripheral.FS_GINTSTS := (MMIS => True, others => <>);
   --
   --        raise Program_Error;
   --     end if;
   --
   --     if Status.OTGINT then
   --        raise Program_Error;
   --     end if;
   --
   --     if Status.SOF then
   --        Self.Global_Peripheral.FS_GINTSTS := (SOF => True, others => <>);
   --
   --        Done := True;
   --        --  raise Program_Error;
   --     end if;
   --
   --     if Status.RXFLVL then
   --        Self.On_RXFLVL;
   --
   --        Done := True;
   --     end if;
   --
   --     if Status.ESUSP then
   --        Self.Global_Peripheral.FS_GINTSTS := (ESUSP => True, others => <>);
   --
   --        return;
   --        --  raise Program_Error;
   --     end if;
   --
   --     if Status.USBSUSP then
   --        Self.Global_Peripheral.FS_GINTSTS := (USBSUSP => True, others => <>);
   --
   --        return;
   --        --  raise Program_Error;
   --     end if;
   --
   --     if Status.USBRST then
   --        Self.Global_Peripheral.FS_GINTSTS := (USBRST => True, others => <>);
   --
   --        if Reset then
   --           raise Program_Error;
   --
   --        else
   --           Reset := True;
   --        end if;
   --
   --        Self.EP_Initialization_On_USB_Reset;
   --        Done := True;
   --     end if;
   --
   --     if Status.ENUMDNE then
   --        Self.Global_Peripheral.FS_GINTSTS.ENUMDNE := True;
   --
   --        Self.EP_Initialization_On_Enumeration_Completion;
   --        Done := True;
   --     end if;
   --
   --     if not Done then
   --        raise Program_Error;
   --     end if;
   end On_Interrupt;

   -------------------------------
   -- On_Out_Endpoint_Interrupt --
   -------------------------------

   procedure On_Out_Endpoint_Interrupt
     (Self : in out OTG_FS_Device_Controller'Class)
   is
      use type A0B.Types.Unsigned_16;

      Status : constant A0B.STM32F401.SVD.USB_OTG_FS.FS_DAINT_OEPINT_Field :=
        Self.Device_Peripheral.FS_DAINT.OEPINT;

   begin
      Logger.OEP_Interrupt (Status);

      --  XXX Process OTG_FS_DAINT & OTG_FS_DOEPINTx

      if (Status and 2#0001#) /= 0 then
         Logger.OEP0_Interrupt (Self.Device_Peripheral.DOEPINT0);

         --  XXX This register doesn't match documentation!

         if Self.Device_Peripheral.DOEPINT0.XFRC then
            Self.Device_Peripheral.DOEPINT0 :=
              (XFRC => True, Reserved_7_31 => 0, others => <>);
            --  Self.Device_Peripheral.DOEPINT0 .XFRC
            --  raise Program_Error;
         end if;

         if Self.Device_Peripheral.DOEPINT0.EPDISD then
            raise Program_Error;
         end if;

         if Self.Device_Peripheral.DOEPINT0.STUP then
            Self.Device_Peripheral.DOEPINT0 :=
              (STUP => True, Reserved_7_31 => 0, others => <>);

            Logger.Setup_Data (Self.Setup_Buffer);

            declare
               Response : A0B.USB.Endpoints.Control.Response_Record;

            begin
               Self.Control_Endpoint.On_Setup_Request
                 (Self.Setup_Buffer, Response);

               case Response.Kind is
                  when A0B.USB.Endpoints.Control.Not_Acknowledge =>
                     raise Program_Error;

                  when A0B.USB.Endpoints.Control.Acknowledge =>
                     Self.Initiate_IN0_Acknowledge;

                  when A0B.USB.Endpoints.Control.Stall =>
                     Self.Initiate_IN0_Stall;

                  when A0B.USB.Endpoints.Control.Data =>
                     Self.Initiate_IN0_Transfer
                       (Response.Buffer, Response.Size);

                  when A0B.USB.Endpoints.Control.Set_Address =>
                     Self.Initiate_IN0_Acknowledge;
                     Self.Internal_Set_Address (Response.Address);
               end case;
            end;
         end if;

         --  if Self.Device_Peripheral.DOEPINT0.OTEPDIS then
         --     raise Program_Error;
         --  end if;

         if Self.Device_Peripheral.DOEPINT0.B2BSTUP then
            raise Program_Error;
         end if;

      end if;

      if (Status and 2#0010#) /= 0 then
         raise Program_Error;
      end if;

      if (Status and 2#0100#) /= 0 then
         Logger.OEP2_Interrupt (Self.Device_Peripheral.DOEPINT2);

         --  Register doesn't match documentation

         if Self.Device_Peripheral.DOEPINT2.XFRC then
            Self.Device_Peripheral.DOEPINT2 :=
              (XFRC => True, Reserved_7_31 => 0, others => <>);

            --  raise Program_Error;

            Self.Endpoint_2.On_Bulk_Out;
         end if;

         if Self.Device_Peripheral.DOEPINT2.EPDISD then
            Self.Device_Peripheral.DOEPINT2 :=
              (EPDISD => True, Reserved_7_31 => 0, others => <>);

            raise Program_Error;
         end if;

         --  STUP and OTEPDIS: Applies only to control OUT endpoints.
         --
         --  if Self.Device_Peripheral.DOEPINT2.STUP then
         --     Self.Device_Peripheral.DOEPINT2 :=
         --       (STUP => True, Reserved_7_31 => 0, others => <>);
         --
         --     raise Program_Error;
         --  end if;
         --
         --  if Self.Device_Peripheral.DOEPINT2.OTEPDIS then
         --     Self.Device_Peripheral.DOEPINT2 :=
         --       (OTEPDIS => True, Reserved_7_31 => 0, others => <>);
         --
         --     raise Program_Error;
         --  end if;

         if Self.Device_Peripheral.DOEPINT2.B2BSTUP then
            Self.Device_Peripheral.DOEPINT2 :=
              (B2BSTUP => True, Reserved_7_31 => 0, others => <>);

            raise Program_Error;
         end if;
      end if;

      if (Status and 2#1000#) /= 0 then
         raise Program_Error;
      end if;
   end On_Out_Endpoint_Interrupt;

   ---------------
   -- On_RXFLVL --
   ---------------

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

      --  PKTSTS_Host_IN_Data_Packet_Received : constant := 2#0010#;
      --  PKTSTS_Host_IN_Transfer_Completed   : constant := 2#0110#;
      --  PKTSTS_Host_Data_Toggle_Error       : constant := 2#0101#;
      --  PKTSTS_Host_Channel_Halted          : constant := 2#0111#;

      PKTSTS_Device_Global_OUT_NAK              : constant := 2#0001#;
      PKTSTS_Device_OUT_Data_Packet_Received    : constant := 2#0010#;
      PKTSTS_Device_OUT_Transfer_Completed      : constant := 2#0011#;
      PKTSTS_Device_SETUP_Transaction_Completed : constant := 2#0100#;
      PKTSTS_Device_SETUP_Data_Packet_Received  : constant := 2#0110#;

   begin
      Logger.RXFLVL (Status);

      if Status.PKTSTS = PKTSTS_Device_Global_OUT_NAK
        and Status.BCNT = 0
        and Status.EPNUM = 0  --  Don't care
        and Status.DPID = 0   --  Don't care

      then
         --  a) Global OUT NAK pattern

         raise Program_Error;

      elsif Status.PKTSTS = PKTSTS_Device_SETUP_Data_Packet_Received
        and Status.BCNT = 8
        and Status.EPNUM = 0
        and Status.DPID = 2#00#   --  DATA0
      then
         --  b) SETUP packet pattern

         --  if Setup then
         --     raise Program_Error;
         --
         --  else
         --     Setup := True;
         --  end if;

         --  SUPCNT := Integer (Self.Device_Peripheral.DOEPTSIZ0.STUPCNT);

         declare
            FIFO : A0B.Types.Unsigned_32
              with Import,
                Volatile, Full_Access_Only,
              Address => System.Storage_Elements.To_Address (16#5000_1000#);
            --  FIFO : Setup_Buffer with Import,
            --    Address => System.Storage_Elements.To_Address (16#5000_1000#);
            B    : array (0 .. 1) of A0B.Types.Unsigned_32
              with Import, Address => Self.Setup_Buffer'Address;

         begin
            --  Buffer := FIFO;
            B(0) := FIFO;
            B(1) := FIFO;
            --  B(2) := FIFO;

            --  Status := GRXSTSRP_Device;
            --  raise Program_Error;
         end;

         --  raise Program_Error;

      elsif Status.PKTSTS = PKTSTS_Device_SETUP_Transaction_Completed
        and Status.BCNT = 0
        and Status.EPNUM = 0
        and Status.DPID = 2#00#  --  Don't care
      then
         --  c) Setup stage done pattern

         --  if Setup_Done then
         --     raise Program_Error;
         --  end if;
         --
         --  Setup_Done := True;

         --  if Self.Device_Peripheral.DOEPTSIZ0.STUPCNT /= 2 then
         --     raise Program_Error;
         --  end if;

         if not Self.Device_Peripheral.DOEPINT0.STUP then
            raise Program_Error;
         end if;

         --  Self.Control_Endpoint.On_Setup_Request (Self.Setup_Buffer);
         --  Status := GRXSTSRP_Device;

         --  raise Program_Error;

      elsif Status.PKTSTS = PKTSTS_Device_OUT_Data_Packet_Received
        and Status.BCNT in 0 .. 1_024
      --  and Status.EPNUM =
      --  and Status.DPID =
      then
         --  d) Data OUT packet pattern

         case Status.EPNUM is
            when 0 =>
               if Status.BCNT = 0 then
                  null;
                  --  raise Program_Error;

               else
                  raise Program_Error;
               end if;

            when 2 =>
               if Status.BCNT = 0 then
                  raise Program_Error;

               else
                  Self.Endpoint_2.Size := A0B.Types.Unsigned_32 (Status.BCNT);
                  Self.Read_FIFO;
                  --
                  --  Self.Endpoint_2.On_Bulk_Out;
               end if;

            when others =>
               raise Program_Error;
         end case;

      elsif Status.PKTSTS = PKTSTS_Device_OUT_Transfer_Completed
        and Status.BCNT = 0
      --  and Status.EPNUM =
        --  and Status.DPID = 0  --  Don't care
      then
         if Status.EPNUM = 0 then
            --  CONTROL has been acquired
            null;

         elsif Status.EPNUM = 2 then
            null;
         else
            raise Program_Error;
         end if;

      else
         --  Status_G := Status;

         raise Program_Error;
      end if;
   end On_RXFLVL;

   ------------------
   -- On_USB_Reset --
   ------------------

   procedure On_USB_Reset (Self : in out OTG_FS_Device_Controller'Class) is
   begin
      Self.EP_Initialization_On_USB_Reset;
   end On_USB_Reset;

   ---------------
   -- Read_FIFO --
   ---------------

   procedure Read_FIFO (Self : in out OTG_FS_Device_Controller'Class) is
      use type A0B.Types.Unsigned_32;
      use type System.Storage_Elements.Storage_Offset;

      FIFO : A0B.Types.Unsigned_32
        with Import,
             Volatile,
             Full_Access_Only,
             Address => System.Storage_Elements.To_Address (16#5000_3000#);

      Count   : A0B.Types.Unsigned_32 :=
        A0B.Types.Unsigned_32 (Self.Endpoint_2.Size) / 4;
      Bytes   : A0B.Types.Unsigned_32 :=
        A0B.Types.Unsigned_32 (Self.Endpoint_2.Size) mod 4;
      Pointer : System.Address := Self.Endpoint_2.Buffer'Address;

   begin
      loop
         exit when Count = 0;

         declare
            B0 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 0;
            B1 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 1;
            B2 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 2;
            B3 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 3;
            V  : constant A0B.Types.Unsigned_32 := FIFO;

         begin
            B0 := A0B.Types.Unsigned_8 (V and 16#0000_00FF#);
            B1 :=
              A0B.Types.Unsigned_8
                (A0B.Types.Shift_Right (V, 8) and 16#0000_00FF#);
            B2 :=
              A0B.Types.Unsigned_8
                (A0B.Types.Shift_Right (V, 16) and 16#0000_00FF#);
            B3 :=
              A0B.Types.Unsigned_8
                (A0B.Types.Shift_Right (V, 24) and 16#0000_00FF#);
         end;

         Count   := @ - 1;
         Pointer := @ + 4;
      end loop;

      if Bytes /= 0 then
         declare
            B0 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 0;
            B1 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 1;
            B2 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 2;
            B3 : A0B.Types.Unsigned_8 with Import, Address => Pointer + 3;
            V  : constant A0B.Types.Unsigned_32 := FIFO;

         begin
            B0    := A0B.Types.Unsigned_8 (V and 16#0000_00FF#);
            Bytes := @ - 1;

            if Bytes /= 0 then
               B1    :=
                 A0B.Types.Unsigned_8
                   (A0B.Types.Shift_Right (V, 8) and 16#0000_00FF#);
               Bytes := @ - 1;
            end if;

            if Bytes /= 0 then
               B2    :=
                 A0B.Types.Unsigned_8
                   (A0B.Types.Shift_Right (V, 16) and 16#0000_00FF#);
               Bytes := @ - 1;
            end if;
         end;
      end if;
   end Read_FIFO;

   -----------------
   -- Receive_OUT --
   -----------------

   overriding procedure Receive_OUT
     (Self        : in out OTG_FS_Endpoint;
      Buffer      : aliased in out A0B.USB.Endpoints.Buffer_Descriptor;
      On_Finished : A0B.Callbacks.Callback;
      Success     : in out Boolean) is
   begin
      raise Program_Error;
   end Receive_OUT;

   -----------------
   -- Transmit_IN --
   -----------------

   overriding procedure Transmit_IN
     (Self        : in out OTG_FS_Endpoint;
      Buffer      : aliased in out A0B.USB.Endpoints.Buffer_Descriptor;
      On_Finished : A0B.Callbacks.Callback;
      Success     : in out Boolean) is
   begin
      if not Success then
         return;
      end if;

      Logger.Transmit_IN1;

      Self.IN_Transfer := Buffer'Unchecked_Access;
      Self.IN_Callback := On_Finished;

      Self.IN_Transfer.Transferred := 0;
      Self.IN_Transfer.State       := A0B.Active;

      Self.Controller.Initiate_IN1_Transfer;
   end Transmit_IN;

   ----------------
   -- Write_FIFO --
   ----------------

   procedure Write_FIFO
     (Self           : in out OTG_FS_Device_Controller'Class;
      FIFO_Address   : System.Address;
      Buffer_Address : System.Address;
      Length         : A0B.Types.Unsigned_32)
   is
      use type A0B.Types.Unsigned_32;
      use type System.Storage_Elements.Storage_Offset;

      FIFO    : A0B.Types.Unsigned_32
        with Import, Volatile, Full_Access_Only, Address => FIFO_Address;

      Count   : A0B.Types.Unsigned_32 := Length / 4;
      Bytes   : A0B.Types.Unsigned_32 := Length mod 4;
      Pointer : System.Address := Buffer_Address;

   begin
      loop
         exit when Count = 0;

         declare
            B0 : constant A0B.Types.Unsigned_8
              with Import, Address => Pointer + 0;
            B1 : constant A0B.Types.Unsigned_8
              with Import, Address => Pointer + 1;
            B2 : constant A0B.Types.Unsigned_8
              with Import, Address => Pointer + 2;
            B3 : constant A0B.Types.Unsigned_8
              with Import, Address => Pointer + 3;

         begin
            FIFO :=
              A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B0), 0)
                or A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B1), 8)
                or A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B2), 16)
                or A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B3), 24);
         end;

         Count   := @ - 1;
         Pointer := @ + 4;
      end loop;

      if Bytes /= 0 then
         declare
            Word : A0B.Types.Unsigned_32 := 0;

         begin
            declare
               B : A0B.Types.Unsigned_8 with Import, Address => Pointer;

            begin
               Word    := A0B.Types.Unsigned_32 (B);
               Pointer := @ + 1;
               Bytes   := @ - 1;
            end;

            if Bytes /= 0 then
               declare
                  B : A0B.Types.Unsigned_8 with Import, Address => Pointer;

               begin
                  Word    :=
                    @ or A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B), 8);
                  Pointer := @ + 1;
                  Bytes   := @ - 1;
               end;
            end if;

            if Bytes /= 0 then
               declare
                  B : A0B.Types.Unsigned_8 with Import, Address => Pointer;

               begin
                  Word    :=
                    @ or A0B.Types.Shift_Left (A0B.Types.Unsigned_32 (B), 16);
                  Pointer := @ + 1;
                  Bytes   := @ - 1;
               end;
            end if;

            FIFO := Word;
         end;
      end if;
   end Write_FIFO;

end A0B.USB.Controllers.STM32F401_OTG_FS;
