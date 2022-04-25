/*
   Copyright (C) 2017-2018 Red Hat, Inc.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:

       * Redistributions of source code must retain the above copyright
         notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above copyright
         notice, this list of conditions and the following disclaimer in
         the documentation and/or other materials provided with the
         distribution.
       * Neither the name of the copyright holder nor the names of its
         contributors may be used to endorse or promote products derived
         from this software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS "AS
   IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
   TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
   PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/*
 * This header contains definition for the device that
 * allows to send streamed data to the server.
 *
 * The device is currently implemented as a VirtIO port inside the
 * guest. The guest should open that device to use this protocol to
 * communicate with the host.
 */

#ifndef SPICE_STREAM_DEVICE_H_
#define SPICE_STREAM_DEVICE_H_

#include <spice/types.h>

/*
 * Structures are all "naturally aligned"
 * containing integers up to 64 bit.
 * All numbers are in little endian format.
 *
 * For security reasons structures should not contain implicit paddings.
 *
 * The protocol can be defined by these states:
 * - Initial. Device just opened. Guest should wait
 *   for a message from the host;
 * - Idle. No streaming allowed;
 * - Ready. Server sent list of possible codecs;
 * - Streaming. Stream active, enabled by the guest.
 */

/* version of the protocol */
#define STREAM_DEVICE_PROTOCOL 1

typedef struct StreamDevHeader {
    /* should be STREAM_DEVICE_PROTOCOL */
    uint8_t protocol_version;
    /* reserved, should be set to 0 */
    uint8_t padding;
    /* as defined in StreamMsgType enumeration */
    uint16_t type;
    /* size of the following message.
     * A message of type STREAM_TYPE_XXX_YYY is represented with a
     * corresponding StreamMsgXxxYyy structure. */
    uint32_t size;
} StreamDevHeader;

typedef enum StreamMsgType {
    /* invalid, do not use */
    STREAM_TYPE_INVALID = 0,
    /* allows to send version information */
    STREAM_TYPE_CAPABILITIES,
    /* send screen resolution */
    STREAM_TYPE_FORMAT,
    /* stream data */
    STREAM_TYPE_DATA,
    /* server ask to start a new stream */
    STREAM_TYPE_START_STOP,
    /* server notify errors to guest */
    STREAM_TYPE_NOTIFY_ERROR,
    /* guest cursor */
    STREAM_TYPE_CURSOR_SET,
    /* guest cursor position */
    STREAM_TYPE_CURSOR_MOVE,
    /* the graphics device display information message (device address and display id) */
    STREAM_TYPE_DEVICE_DISPLAY_INFO,
    /* video encoding quality indicator message */
    STREAM_TYPE_QUALITY_INDICATOR,
} StreamMsgType;

typedef enum StreamCapabilities {
    /* handling of STREAM_TYPE_QUALITY_INDICATOR messages */
    STREAM_CAP_QUALITY_INDICATOR,
    STREAM_CAP_END // this must be the last
} StreamCapabilities;

/* Generic extension capabilities.
 * This is a set of bits to specify which capabilities host and guest support.
 * This message is sent by the host to the guest or by the guest to the host.
 * Should be sent as first message.
 * If it is not sent, it means that guest/host doesn't support any extension.
 * Guest should send this as a reply from same type of message
 * from the host.
 * This message should be limited to STREAM_MSG_CAPABILITIES_MAX_BYTES. This
 * allows plenty of negotiations.
 *
 * States allowed: Initial(host), Idle(guest)
 *   state will change to Idle.
 */
typedef struct StreamMsgCapabilities {
    uint8_t capabilities[0];
} StreamMsgCapabilities;

#define STREAM_MSG_CAPABILITIES_MAX_BYTES 1024

/* Define the format of the stream, start a new stream.
 * This message is sent by the guest to the host to
 * tell the host the new stream format.
 *
 * States allowed: Ready
 *   state will change to Streaming.
 */
typedef struct StreamMsgFormat {
    /* screen resolution/stream size */
    uint32_t width;
    uint32_t height;
    /* as defined in SpiceVideoCodecType enumeration */
    uint8_t codec;
    uint8_t padding1[3];
} StreamMsgFormat;

/* This message contains just raw data stream.
 * This message is sent by the guest to the host.
 *
 * States allowed: Streaming
 */
typedef struct StreamMsgData {
    uint8_t data[0];
} StreamMsgData;

/* This message contains information about the graphics device and monitor
 * belonging to a particular video stream (which maps to a channel) from
 * the streaming agent.
 *
 * The device_address is the hardware address of the device (e.g. PCI),
 * device_display_id is the id of the monitor on the device.
 *
 * The supported device address format is:
 * "pci/<DOMAIN>/<SLOT>.<FUNCTION>/.../<SLOT>.<FUNCTION>"
 *
 * The "pci" identifies the rest of the string as a PCI address. It is the only
 * supported address at the moment, other identifiers can be introduced later.
 * <DOMAIN> is the PCI domain, followed by <SLOT>.<FUNCTION> of any PCI bridges
 * in the chain leading to the device. The last <SLOT>.<FUNCTION> is the
 * graphics device. All of <DOMAIN>, <SLOT>, <FUNCTION> are hexadecimal numbers
 * with the following number of digits:
 *   <DOMAIN>: 4
 *   <SLOT>: 2
 *   <FUNCTION>: 1
 *
 * Sent from the streaming agent to the server.
 */
typedef struct StreamMsgDeviceDisplayInfo {
    uint32_t stream_id;
    uint32_t device_display_id;
    uint32_t device_address_len;
    uint8_t device_address[0];  // a zero-terminated string
} StreamMsgDeviceDisplayInfo;

/* This message contains a quality indicator string, generated by the
 * streaming agent. It is intended to be used by a module running of
 * the server to adjust the streaming quality.
 *
 * The format of the string message is not specified because
 * module-specific.
 *
 * This message is sent by the guest to the host.
 *
 * States allowed: any
 *
 * Capability required: STREAM_CAP_QUALITY_INDICATOR
 */
typedef struct StreamMsgQualityIndicator {
    uint8_t quality[0];  // a zero-terminated string
} StreamMsgQualityIndicator;

/* Tell to stop current stream and possibly start a new one.
 * This message is sent by the host to the guest.
 * Allows to communicate the codecs supported by the clients.
 * The agent should stop the old stream and if any codec in the
 * list is supported start streaming (as Mjpeg is always supported
 * agent should stop only on a real stop request).
 *
 * States allowed: any
 *   state will change to Idle (no codecs) or Ready
 */
typedef struct StreamMsgStartStop {
    /* supported codecs, 0 to stop streaming */
    uint8_t num_codecs;
    /* as defined in SpiceVideoCodecType enumeration */
    uint8_t codecs[0];
} StreamMsgStartStop;

/* Tell guest about invalid protocol.
 * This message is sent by the host to the guest.
 * The server will stop processing data from the guest.
 *
 * States allowed: any
 */
typedef struct StreamMsgNotifyError {
    /* numeric error code.
     * Currently not defined, set to 0.
     */
    uint32_t error_code;
    /* String message, UTF-8 encoded.
     * This field terminate with the message.
     * Not necessary NUL-terminated.
     */
    uint8_t msg[0];
} StreamMsgNotifyError;

#define STREAM_MSG_CURSOR_SET_MAX_WIDTH  1024
#define STREAM_MSG_CURSOR_SET_MAX_HEIGHT 1024

/* Guest cursor.
 * This message is sent by the guest to the host.
 *
 * States allowed: Streaming
 */
typedef struct StreamMsgCursorSet {
    /* basic cursor information */
    /* for security reasons width and height should
     * be limited to STREAM_MSG_CURSOR_SET_MAX_WIDTH and
     * STREAM_MSG_CURSOR_SET_MAX_HEIGHT */
    uint16_t width;
    uint16_t height;
    uint16_t hot_spot_x;
    uint16_t hot_spot_y;
    /* Cursor type, as defined by SpiceCursorType.
     * Only ALPHA, COLOR24 and COLOR32 are allowed by this protocol
     */
    uint8_t type;

    uint8_t padding1[3];

    /* cursor data.
     * Format and size depends on cursor_header type and size
     */
    uint8_t data[0];
} StreamMsgCursorSet;

/* Guest cursor position
 * This message is sent by the guest to the host.
 *
 * States allowed: Streaming
 */
typedef struct StreamMsgCursorMove {
    int32_t x;
    int32_t y;
} StreamMsgCursorMove;

#endif /* SPICE_STREAM_DEVICE_H_ */
