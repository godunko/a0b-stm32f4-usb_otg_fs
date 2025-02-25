--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

pragma Restrictions (No_Elaboration_Code);

with A0B.STM32F401.SVD.USB_OTG_FS;

package A0B.USB.Controllers.STM32F401_OTG_FS
  with Preelaborate
is

   type OTG_FS_Device_Controller
     (Global_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_GLOBAL_Peripheral;
      Device_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Peripheral)
     is tagged limited private
       with Preelaborable_Initialization;

   procedure Initialize (Self : in out OTG_FS_Device_Controller'Class);

   procedure Enable (Self : in out OTG_FS_Device_Controller'Class);

private

   type OTG_FS_Device_Controller
     (Global_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_GLOBAL_Peripheral;
      Device_Peripheral : not null access
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Peripheral)
     is tagged limited null record;

   procedure On_Interrupt (Self : in out OTG_FS_Device_Controller'Class);

end A0B.USB.Controllers.STM32F401_OTG_FS;
