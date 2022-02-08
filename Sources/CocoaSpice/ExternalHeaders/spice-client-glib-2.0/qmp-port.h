/* -*- Mode: C; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
  Copyright (C) 2018 Red Hat, Inc.

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
#ifndef QMP_PORT_H_
#define QMP_PORT_H_

#if !defined(__SPICE_CLIENT_H_INSIDE__) && !defined(SPICE_COMPILATION)
#warning "Only <spice-client.h> can be included directly"
#endif

#include <glib-object.h>
#include "channel-port.h"

G_BEGIN_DECLS

#define SPICE_TYPE_QMP_PORT            (spice_qmp_port_get_type ())
#define SPICE_QMP_PORT(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), SPICE_TYPE_QMP_PORT, SpiceQmpPort))
#define SPICE_QMP_PORT_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass), SPICE_TYPE_QMP_PORT, SpiceQmpPortClass))
#define SPICE_IS_QMP_PORT(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), SPICE_TYPE_QMP_PORT))
#define SPICE_IS_QMP_PORT_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass), SPICE_TYPE_QMP_PORT))
#define SPICE_QMP_PORT_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj), SPICE_TYPE_QMP_PORT, SpiceQmpPortClass))

/**
 * SpiceQmpPort:
 *
 * Opaque data structure.
 * Since: 0.36
 */
typedef struct _SpiceQmpPort SpiceQmpPort;
typedef struct _SpiceQmpPortClass SpiceQmpPortClass;

/**
 * SpiceQmpPortVmAction:
 * @SPICE_QMP_PORT_VM_ACTION_QUIT: This command will cause the VM process to exit gracefully.
 * @SPICE_QMP_PORT_VM_ACTION_RESET: Performs a hard reset of the VM.
 * @SPICE_QMP_PORT_VM_ACTION_POWER_DOWN: Performs a power down operation.
 * @SPICE_QMP_PORT_VM_ACTION_PAUSE: Stop all VCPU execution.
 * @SPICE_QMP_PORT_VM_ACTION_CONTINUE: Resume all VCPU execution.
 * @SPICE_QMP_PORT_VM_ACTION_LAST: the last enum value.
 *
 * An action to perform on the VM.
 *
 * Since: 0.36
 **/
typedef enum SpiceQmpPortVmAction {
    SPICE_QMP_PORT_VM_ACTION_QUIT,
    SPICE_QMP_PORT_VM_ACTION_RESET,
    SPICE_QMP_PORT_VM_ACTION_POWER_DOWN,
    SPICE_QMP_PORT_VM_ACTION_PAUSE,
    SPICE_QMP_PORT_VM_ACTION_CONTINUE,

    SPICE_QMP_PORT_VM_ACTION_LAST,
} SpiceQmpPortVmAction;

/**
 * SpiceQmpStatus:
 * @version: the structure version
 * @running: true if all VCPUs are runnable, false if not runnable
 * @singlestep: true if VCPUs are in single-step mode
 * @status: the virtual machine run state
 *
 * Information about VCPU run state.
 *
 * Since: 0.36
 **/
typedef struct _SpiceQmpStatus {
    /*< private >*/
    gint ref;

    /*< public >*/
    gint version;

    gboolean running;
    gboolean singlestep;
    gchar *status;
} SpiceQmpStatus;

GType spice_qmp_port_get_type(void);

SpiceQmpPort *spice_qmp_port_get(SpicePortChannel *channel);

void spice_qmp_port_vm_action_async(SpiceQmpPort *self,
                                    SpiceQmpPortVmAction action,
                                    GCancellable *cancellable,
                                    GAsyncReadyCallback callback,
                                    gpointer user_data);

gboolean spice_qmp_port_vm_action_finish(SpiceQmpPort *self,
                                         GAsyncResult *result,
                                         GError **error);

GType spice_qmp_status_get_type(void);

SpiceQmpStatus *spice_qmp_status_ref(SpiceQmpStatus *status);
void spice_qmp_status_unref(SpiceQmpStatus *status);

void spice_qmp_port_query_status_async(SpiceQmpPort *self,
                                       GCancellable *cancellable,
                                       GAsyncReadyCallback callback,
                                       gpointer user_data);

SpiceQmpStatus *spice_qmp_port_query_status_finish(SpiceQmpPort *self,
                                                   GAsyncResult *result,
                                                   GError **error);

G_END_DECLS

#endif /* QMP_PORT_H_ */
