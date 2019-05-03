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

/// \file DataCompressor.h
/// \brief DataCompressor does compression on a block of data.  
/// \details Not very good compression, but it's small and fast so is something you can use per-message at runtime.
///


#ifndef __DATA_COMPRESSOR_H
#define __DATA_COMPRESSOR_H

#include "DS_HuffmanEncodingTree.h"
#include "Export.h"

namespace CrabNet
{

/// \brief Does compression on a block of data.  Not very good compression, but it's small and fast so is something you can compute at runtime.
class RAK_DLL_EXPORT DataCompressor
{
public:
    // GetInstance() and DestroyInstance(instance*)
    STATIC_FACTORY_DECLARATIONS(DataCompressor)

    static void Compress( unsigned char *userData, unsigned sizeInBytes, CrabNet::BitStream * output );
    static unsigned DecompressAndAllocate( CrabNet::BitStream * input, unsigned char **output );
};

} // namespace CrabNet

#endif