/* -*- Mode: C; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
   Copyright (C) 2011 Red Hat, Inc.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, see <http://www.gnu.org/licenses/>.
*/
#ifndef __SPICE_CLIENT_SMARTCARD_CHANNEL_H__
#define __SPICE_CLIENT_SMARTCARD_CHANNEL_H__

#if !defined(__SPICE_CLIENT_H_INSIDE__) && !defined(SPICE_COMPILATION)
#warning "Only <spice-client.h> can be included directly"
#endif

#include "spice-client.h"

G_BEGIN_DECLS

#define SPICE_TYPE_SMARTCARD_CHANNEL            (spice_smartcard_channel_get_type())
#define SPICE_SMARTCARD_CHANNEL(obj)            (G_TYPE_CHECK_INSTANCE_CAST((obj), SPICE_TYPE_SMARTCARD_CHANNEL, SpiceSmartcardChannel))
#define SPICE_SMARTCARD_CHANNEL_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST((klass), SPICE_TYPE_SMARTCARD_CHANNEL, SpiceSmartcardChannelClass))
#define SPICE_IS_SMARTCARD_CHANNEL(obj)         (G_TYPE_CHECK_INSTANCE_TYPE((obj), SPICE_TYPE_SMARTCARD_CHANNEL))
#define SPICE_IS_SMARTCARD_CHANNEL_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE((klass), SPICE_TYPE_SMARTCARD_CHANNEL))
#define SPICE_SMARTCARD_CHANNEL_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS((obj), SPICE_TYPE_SMARTCARD_CHANNEL, SpiceSmartcardChannelClass))

typedef struct _SpiceSmartcardChannel SpiceSmartcardChannel;
typedef struct _SpiceSmartcardChannelClass SpiceSmartcardChannelClass;
typedef struct _SpiceSmartcardChannelPrivate SpiceSmartcardChannelPrivate;

/**
 * SpiceSmartcardChannel:
 *
 * The #SpiceSmartcardChannel struct is opaque and should not be accessed directly.
 */
struct _SpiceSmartcardChannel {
    SpiceChannel parent;

    /*< private >*/
    SpiceSmartcardChannelPrivate *priv;
    /* Do not add fields to this struct */
};

/**
 * SpiceSmartcardChannelClass:
 * @parent_class: Parent class.
 *
 * Class structure for #SpiceSmartcardChannel.
 */
struct _SpiceSmartcardChannelClass {
    SpiceChannelClass parent_class;

    /* signals */

    /*< private >*/
    /* Do not add fields to this struct */
};

GType spice_smartcard_channel_get_type(void);

G_END_DECLS

#endif /* __SPICE_CLIENT_SMARTCARD_CHANNEL_H__ */
