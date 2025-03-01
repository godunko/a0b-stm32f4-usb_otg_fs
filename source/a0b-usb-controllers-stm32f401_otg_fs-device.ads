--
--  Copyright (C) 2025, Vadim Godunko <vgodunko@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

package A0B.USB.Controllers.STM32F401_OTG_FS.Device
  with Elaborate_Body
is

   OTG_FS : aliased OTG_FS_Device_Controller
     (Global_Peripheral =>
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_GLOBAL_Periph'Access,
      Device_Peripheral =>
        A0B.STM32F401.SVD.USB_OTG_FS.OTG_FS_DEVICE_Periph'Access);

end A0B.USB.Controllers.STM32F401_OTG_FS.Device;
