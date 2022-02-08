/*
   Copyright (C) 2010-2015 Red Hat, Inc.

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

#ifndef __SPICE_FILE_TRANSFER_TASK_H__
#define __SPICE_FILE_TRANSFER_TASK_H__

#if !defined(__SPICE_CLIENT_H_INSIDE__) && !defined(SPICE_COMPILATION)
#warning "Only <spice-client.h> can be included directly"
#endif

#include "spice-client.h"

#include <glib-object.h>

G_BEGIN_DECLS

#define SPICE_TYPE_FILE_TRANSFER_TASK spice_file_transfer_task_get_type()

#define SPICE_FILE_TRANSFER_TASK(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), SPICE_TYPE_FILE_TRANSFER_TASK, SpiceFileTransferTask))
#define SPICE_FILE_TRANSFER_TASK_CLASS(klass) (G_TYPE_CHECK_CLASS_CAST((klass), SPICE_TYPE_FILE_TRANSFER_TASK, SpiceFileTransferTaskClass))
#define SPICE_IS_FILE_TRANSFER_TASK(obj) (G_TYPE_CHECK_INSTANCE_TYPE((obj), SPICE_TYPE_FILE_TRANSFER_TASK))
#define SPICE_IS_FILE_TRANSFER_TASK_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE((klass), SPICE_TYPE_FILE_TRANSFER_TASK))
#define SPICE_FILE_TRANSFER_TASK_GET_CLASS(obj) (G_TYPE_INSTANCE_GET_CLASS((obj), SPICE_TYPE_FILE_TRANSFER_TASK, SpiceFileTransferTaskClass))

typedef struct _SpiceFileTransferTask SpiceFileTransferTask;
typedef struct _SpiceFileTransferTaskClass SpiceFileTransferTaskClass;

GType spice_file_transfer_task_get_type(void) G_GNUC_CONST;

char* spice_file_transfer_task_get_filename(SpiceFileTransferTask *self);
void spice_file_transfer_task_cancel(SpiceFileTransferTask *self);
guint64 spice_file_transfer_task_get_total_bytes(SpiceFileTransferTask *self);
guint64 spice_file_transfer_task_get_transferred_bytes(SpiceFileTransferTask *self);
double spice_file_transfer_task_get_progress(SpiceFileTransferTask *self);

G_END_DECLS

#endif /* __SPICE_FILE_TRANSFER_TASK_H__ */
