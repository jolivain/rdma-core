# SPDX-License-Identifier: (GPL-2.0 OR Linux-OpenIB)
# Copyright 2020 Amazon.com, Inc. or its affiliates. All rights reserved.

cimport pyverbs.providers.efa.efadv_enums as dve
cimport pyverbs.providers.efa.libefa as dv

from pyverbs.base import PyverbsRDMAErrno, PyverbsRDMAError
from pyverbs.pd cimport PD
from pyverbs.qp cimport QP, QPInitAttr


def dev_cap_to_str(flags):
    l = {
            dve.EFADV_DEVICE_ATTR_CAPS_RDMA_READ: 'RDMA Read',
            dve.EFADV_DEVICE_ATTR_CAPS_RNR_RETRY: 'RNR Retry',
    }
    return bitmask_to_str(flags, l)


def bitmask_to_str(bits, values):
    numeric_bits = bits
    flags = []
    for k, v in sorted(values.items()):
        if bits & k:
            flags.append(v)
            bits -= k
    if bits:
        flags.append(f'??({bits:x})')
    if not flags:
        flags.append('None')
    return ', '.join(flags) + f' ({numeric_bits:x})'


cdef class EfaContext(Context):
    """
    Represent efa context, which extends Context.
    """
    def __init__(self, name=''):
        """
        Open an efa device
        :param name: The RDMA device's name (used by parent class)
        :return: None
        """
        super().__init__(name=name)

    def query_efa_device(self):
        """
        Queries the provider for device-specific attributes.
        :return: An EfaDVDeviceAttr containing the attributes.
        """
        dv_attr = EfaDVDeviceAttr()
        rc = dv.efadv_query_device(self.context, &dv_attr.device_attr, sizeof(dv_attr.device_attr))
        if rc:
            raise PyverbsRDMAError(f'Failed to query efa device {self.name}', rc)
        return dv_attr


cdef class EfaDVDeviceAttr(PyverbsObject):
    """
    Represents efadv_context struct, which exposes efa-specific capabilities,
    reported by efadv_query_device.
    """
    @property
    def comp_mask(self):
        return self.device_attr.comp_mask

    @property
    def max_sq_wr(self):
        return self.device_attr.max_sq_wr

    @property
    def max_rq_wr(self):
        return self.device_attr.max_rq_wr

    @property
    def max_sq_sge(self):
        return self.device_attr.max_sq_sge

    @property
    def max_rq_sge(self):
        return self.device_attr.max_rq_sge

    @property
    def inline_buf_size(self):
        return self.device_attr.inline_buf_size

    @property
    def device_caps(self):
        return self.device_attr.device_caps

    @property
    def max_rdma_size(self):
        return self.device_attr.max_rdma_size

    def __str__(self):
        print_format = '{:20}: {:<20}\n'
        return print_format.format('comp_mask', self.device_attr.comp_mask) + \
            print_format.format('Max SQ WR', self.device_attr.max_sq_wr) + \
            print_format.format('Max RQ WR', self.device_attr.max_rq_wr) + \
            print_format.format('Max SQ SQE', self.device_attr.max_sq_sge) + \
            print_format.format('Max RQ SQE', self.device_attr.max_rq_sge) + \
            print_format.format('Inline buffer size', self.device_attr.inline_buf_size) + \
            print_format.format('Device Capabilities', dev_cap_to_str(self.device_attr.device_caps)) + \
            print_format.format('Max RDMA Size', self.device_attr.max_rdma_size)


cdef class EfaDVAHAttr(PyverbsObject):
    """
    Represents efadv_ah_attr struct
    """
    @property
    def comp_mask(self):
        return self.ah_attr.comp_mask

    @property
    def ahn(self):
        return self.ah_attr.ahn

    def __str__(self):
        print_format = '{:20}: {:<20}\n'
        return print_format.format('comp_mask', self.ah_attr.comp_mask) + \
            print_format.format('ahn', self.ah_attr.ahn)


cdef class EfaAH(AH):
    def query_efa_ah(self):
        """
        Queries the provider for EFA specific AH attributes.
        :return: An EfaDVAHAttr containing the attributes.
        """
        ah_attr = EfaDVAHAttr()
        err = dv.efadv_query_ah(self.ah, &ah_attr.ah_attr, sizeof(ah_attr.ah_attr))
        if err:
            raise PyverbsRDMAError('Failed to query efa ah', err)
        return ah_attr


cdef class SRDQP(QP):
    """
    Initializes an SRD QP according to the user-provided data.
    :param pd: PD object
    :param init_attr: QPInitAttr object
    :return: An initialized SRDQP
    """
    def __init__(self, PD pd not None, QPInitAttr init_attr not None):
        pd.add_ref(self)
        self.qp = dv.efadv_create_driver_qp(pd.pd, &init_attr.attr, dve.EFADV_QP_DRIVER_TYPE_SRD)
        if self.qp == NULL:
            raise PyverbsRDMAErrno('Failed to create SRD QP')
        super().__init__(pd, init_attr)
