/* -*- Mode: C; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
   Copyright (C) 2010 Red Hat, Inc.

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
#ifndef __SPICE_CLIENT_DISPLAY_CHANNEL_H__
#define __SPICE_CLIENT_DISPLAY_CHANNEL_H__

#if !defined(__SPICE_CLIENT_H_INSIDE__) && !defined(SPICE_COMPILATION)
#warning "Only <spice-client.h> can be included directly"
#endif

#include "spice-client.h"

G_BEGIN_DECLS

#define SPICE_TYPE_DISPLAY_CHANNEL            (spice_display_channel_get_type())
#define SPICE_DISPLAY_CHANNEL(obj)            (G_TYPE_CHECK_INSTANCE_CAST((obj), SPICE_TYPE_DISPLAY_CHANNEL, SpiceDisplayChannel))
#define SPICE_DISPLAY_CHANNEL_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST((klass), SPICE_TYPE_DISPLAY_CHANNEL, SpiceDisplayChannelClass))
#define SPICE_IS_DISPLAY_CHANNEL(obj)         (G_TYPE_CHECK_INSTANCE_TYPE((obj), SPICE_TYPE_DISPLAY_CHANNEL))
#define SPICE_IS_DISPLAY_CHANNEL_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE((klass), SPICE_TYPE_DISPLAY_CHANNEL))
#define SPICE_DISPLAY_CHANNEL_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS((obj), SPICE_TYPE_DISPLAY_CHANNEL, SpiceDisplayChannelClass))

typedef struct _SpiceDisplayChannel SpiceDisplayChannel;
typedef struct _SpiceDisplayChannelClass SpiceDisplayChannelClass;
typedef struct _SpiceDisplayChannelPrivate SpiceDisplayChannelPrivate;

#define SPICE_TYPE_GL_SCANOUT (spice_gl_scanout_get_type ())

/**
 * SpiceGlScanout:
 * @fd: a drm DMABUF file that can be imported with eglCreateImageKHR
 * @width: width of the scanout
 * @height: height of the scanout
 * @stride: stride of the scanout
 * @format: the drm fourcc format
 * @y0top: orientation of the scanout
 *
 * Holds the information necessary for using the GL display scanout.
 **/
typedef struct _SpiceGlScanout SpiceGlScanout;
struct _SpiceGlScanout {
    gint fd;
    guint32 width;
    guint32 height;
    guint32 stride;
    guint32 format;
    gboolean y0top;
};

/**
 * SpiceDisplayMonitorConfig:
 * @id: monitor id
 * @surface_id: monitor surface id
 * @x: x position of the monitor
 * @y: y position of the monitor
 * @width: width of the monitor
 * @height: height of the monitor
 *
 * Holds a monitor configuration.
 **/
typedef struct _SpiceDisplayMonitorConfig SpiceDisplayMonitorConfig;
struct _SpiceDisplayMonitorConfig {
    guint id;
    guint surface_id;
    guint x;
    guint y;
    guint width;
    guint height;
};

/**
 * SpiceDisplayPrimary:
 * @format: primary buffer format
 * @width: width of the primary
 * @height: height of the primary
 * @stride: stride of the primary
 * @shmid: identifier of the shared memory segment associated with
 * the @data, or -1 if not shm
 * @data: pointer to primary buffer
 * @marked: whether the display is marked ready
 *
 * Holds the information necessary to use the primary surface.
 **/
typedef struct _SpiceDisplayPrimary SpiceDisplayPrimary;
struct _SpiceDisplayPrimary {
    enum SpiceSurfaceFmt format;
    gint width;
    gint height;
    gint stride;
    gint shmid;
    guint8 *data;
    gboolean marked;
};

/**
 * SpiceDisplayChannel:
 *
 * The #SpiceDisplayChannel struct is opaque and should not be accessed directly.
 */
struct _SpiceDisplayChannel {
    SpiceChannel parent;

    /*< private >*/
    SpiceDisplayChannelPrivate *priv;
    /* Do not add fields to this struct */
};

/**
 * SpiceDisplayChannelClass:
 * @parent_class: Parent class.
 * @display_primary_create: Signal class handler for the #SpiceDisplayChannel::display-primary-create signal.
 * @display_primary_destroy: Signal class handler for the #SpiceDisplayChannel::display-primary-destroy signal.
 * @display_invalidate: Signal class handler for the #SpiceDisplayChannel::display-invalidate signal.
 * @display_mark: Signal class handler for the #SpiceDisplayChannel::display-mark signal.
 *
 * Class structure for #SpiceDisplayChannel.
 */
struct _SpiceDisplayChannelClass {
    SpiceChannelClass parent_class;

    /* signals */
    void (*display_primary_create)(SpiceChannel *channel, gint format,
                                   gint width, gint height, gint stride,
                                   gint shmid, gpointer data);
    void (*display_primary_destroy)(SpiceChannel *channel);
    void (*display_invalidate)(SpiceChannel *channel,
                               gint x, gint y, gint w, gint h);
    void (*display_mark)(SpiceChannel *channel,
                         gboolean mark);

    /*< private >*/
};

GType	        spice_display_channel_get_type(void);
gboolean        spice_display_channel_get_primary(SpiceChannel *channel, guint32 surface_id,
                                                  SpiceDisplayPrimary *primary);

void spice_display_channel_change_preferred_compression(SpiceChannel *channel, gint compression);
void spice_display_channel_change_preferred_video_codec_type(SpiceChannel *channel, gint codec_type);

GType           spice_gl_scanout_get_type     (void) G_GNUC_CONST;
void            spice_gl_scanout_free         (SpiceGlScanout *scanout);

const SpiceGlScanout* spice_display_channel_get_gl_scanout(SpiceDisplayChannel *channel);
void spice_display_channel_gl_draw_done(SpiceDisplayChannel *channel);

#ifndef SPICE_DISABLE_DEPRECATED
G_DEPRECATED_FOR(spice_display_channel_change_preferred_compression)
void spice_display_change_preferred_compression(SpiceChannel *channel, gint compression);
G_DEPRECATED_FOR(spice_display_channel_change_preferred_video_codec_type)
void spice_display_change_preferred_video_codec_type(SpiceChannel *channel, gint codec_type);
G_DEPRECATED_FOR(spice_display_channel_get_gl_scanout)
const SpiceGlScanout* spice_display_get_gl_scanout(SpiceDisplayChannel *channel);
G_DEPRECATED_FOR(spice_display_channel_get_primary)
gboolean spice_display_get_primary(SpiceChannel *channel, guint32 surface_id,
                                   SpiceDisplayPrimary *primary);
G_DEPRECATED_FOR(spice_display_channel_gl_draw_done)
void spice_display_gl_draw_done(SpiceDisplayChannel *channel);
#endif

G_END_DECLS

#endif /* __SPICE_CLIENT_DISPLAY_CHANNEL_H__ */
