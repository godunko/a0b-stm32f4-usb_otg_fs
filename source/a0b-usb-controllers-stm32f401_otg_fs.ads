--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

--  pragma Restrictions (No_Elaboration_Code);

with System;

private with A0B.Callbacks;

with A0B.STM32F401.SVD.USB_OTG_FS;

package A0B.USB.Controllers.STM32F401_OTG_FS
  with Preelaborate
is

   type OTG_FS_Device_Controller
     (Global_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_GLOBAL_Peripheral;
      Device_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Peripheral)
     is limited new Abstract_Device_Controller with private
       with Preelaborable_Initialization;

   procedure Initialize (Self : in out OTG_FS_Device_Controller'Class);

   procedure Enable (Self : in out OTG_FS_Device_Controller'Class);

private

   type OTG_FS_Endpoint
     (Controller : not null access OTG_FS_Device_Controller'Class)
   is limited new A0B.USB.Endpoints.Abstract_Endpoint with record
      --  OUT_Transfer : access A0B.USB.Endpoints.Buffer_Descriptor;
      IN_Transfer  : access A0B.USB.Endpoints.Buffer_Descriptor;
   end record;

   overriding procedure Transmit_IN
     (Self        : in out OTG_FS_Endpoint;
      Buffer      : aliased in out A0B.USB.Endpoints.Buffer_Descriptor;
      On_Finished : A0B.Callbacks.Callback;
      Success     : in out Boolean);

   overriding procedure Receive_OUT
     (Self        : in out OTG_FS_Endpoint;
      Buffer      : aliased in out A0B.USB.Endpoints.Buffer_Descriptor;
      On_Finished : A0B.Callbacks.Callback;
      Success     : in out Boolean);

   type OTG_FS_Device_Controller
     (Global_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_GLOBAL_Peripheral;
      Device_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Peripheral)
   is limited new Abstract_Device_Controller with record
      Setup_Buffer : A0B.USB.Endpoints.Control.Setup_Data_Buffer;
      IN_Buffer    : System.Address;
      IN_Size      : A0B.Types.Unsigned_16;

      EP1          : aliased OTG_FS_Endpoint (OTG_FS_Device_Controller'Access);
      EP2          : aliased OTG_FS_Endpoint (OTG_FS_Device_Controller'Access);
      EP3          : aliased OTG_FS_Endpoint (OTG_FS_Device_Controller'Access);
   end record;

   procedure On_Interrupt (Self : in out OTG_FS_Device_Controller'Class);

   --  overriding procedure Do_IN
   --    (Self : in out OTG_FS_Device_Controller;
   --     Data : A0B.Types.Arrays.Unsigned_8_Array);

   overriding procedure Configuration_Set
     (Self : in out OTG_FS_Device_Controller);

   --  overriding procedure EP1_Send
   --    (Self   : in out OTG_FS_Device_Controller;
   --     Buffer : System.Address;
   --     Size   : A0B.Types.Unsigned_16);

   overriding function Get_Endpoint
     (Self     : in out OTG_FS_Device_Controller;
      Endpoint : A0B.USB.Endpoint_Number)
      return not null access A0B.USB.Endpoints.Abstract_Endpoint'Class;

end A0B.USB.Controllers.STM32F401_OTG_FS;
