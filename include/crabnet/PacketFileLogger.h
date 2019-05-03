/*
 *  Copyright (c) 2014, Oculus VR, Inc.
 *  Copyright (c) 2016-2018, TES3MP Team
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

/// \file
/// \brief This will write all incoming and outgoing network messages to a file
///


#include "NativeFeatureIncludes.h"
#if _CRABNET_SUPPORT_PacketLogger==1

#ifndef __PACKET_FILE_LOGGER_H_
#define __PACKET_FILE_LOGGER_H_

#include "PacketLogger.h"
#include <stdio.h>

namespace CrabNet
{

/// \ingroup PACKETLOGGER_GROUP
/// \brief Packetlogger that outputs to a file
class RAK_DLL_EXPORT  PacketFileLogger : public PacketLogger
{
public:
    PacketFileLogger();
    virtual ~PacketFileLogger();
    void StartLog(const char *filenamePrefix);
    virtual void WriteLog(const char *str);
protected:
    FILE *packetLogFile;
};

} // namespace CrabNet

#endif

#endif // _CRABNET_SUPPORT_*