
cimport numpy

# local imports
from pysph.base.particle_array cimport ParticleArray
from pysph.base.carray cimport DoubleArray, IntArray
from pysph.base.point cimport Point

from pysph.base.kernels cimport MultidimensionalKernel


################################################################################
# `SPHFunctionParticle` class.
################################################################################
cdef class SPHFunctionParticle:
    cdef public ParticleArray source, dest
    cdef public str h, m, rho, p, e, x, y, z, u, v, w
    cdef public str tmpx, tmpy, tmpz, type
        
    cdef public DoubleArray s_h, s_m, s_rho, d_h, d_m, d_rho
    cdef public DoubleArray s_x, s_y, s_z, d_x, d_y, d_z
    cdef public DoubleArray s_u, s_v, s_w, d_u, d_v, d_w
    cdef public DoubleArray s_p, s_e, d_p, d_e	

    cdef public DoubleArray rkpm_d_beta1, rkpm_d_beta2, rkpm_d_beta3
    cdef public DoubleArray rkpm_d_alpha, rkpm_d_dalphadx, rkpm_d_dalphady
    cdef public DoubleArray rkpm_d_dbeta1dx, rkpm_d_dbeta1dy
    cdef public DoubleArray rkpm_d_dbeta2dx, rkpm_d_dbeta2dy
    
    cdef public DoubleArray d_beta1, d_beta2, d_beta3, d_alpha
    cdef public DoubleArray d_alpha_grad1, d_alpha_grad2, d_alpha_grad3

    cdef public Point _src
    cdef public Point _dst
    
    cdef public str name, id

    cdef public bint kernel_gradient_correction	
    cdef public bint first_order_kernel_correction
    cdef public bint rkpm_first_order_correction

    cpdef setup_arrays(self)

    cpdef int output_fields(self) except -1

    cdef void eval(self, int source_pid, int dest_pid, 
                   MultidimensionalKernel kernel, double *nr, double *dnr)

    cdef double rkpm_first_order_kernel_correction(self, int dest_pid)

    cdef double rkpm_first_order_gradient_correction(self, int dest_pid)

################################################################################
# `SPHFunctionPoint` class.
################################################################################
cdef class SPHFunctionPoint:
    cdef public ParticleArray source
    cdef public str h, m, rho, p, e, x, y, z, u, v, w
    cdef public str tmpx, tmpy, tmpz
        
    cdef public DoubleArray s_h, s_m, s_rho, d_h, d_m, d_rho
    cdef public DoubleArray s_p, s_e, d_p, d_e
    cdef public DoubleArray s_x, s_y, s_z, d_x, d_y, d_z
    cdef public DoubleArray s_u, s_v, s_w, d_u, d_v, d_w

    cdef public Point _src, _dst
    
    cpdef setup_arrays(self)
    cpdef int output_fields(self) except -1

    cdef void eval(self, Point pnt, int dest_pid, 
                   MultidimensionalKernel kernel, double *nr, double *dnr)

    cpdef py_eval(self, Point pnt, int dest_pid, 
                  MultidimensionalKernel kernel, numpy.ndarray
                  nr, numpy.ndarray dnr)

##############################################################################
