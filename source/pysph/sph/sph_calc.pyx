"""
General purpose code for SPH computations.

This module provides the SPHCalc class, which does the actual SPH summation.
    
"""

from libc.stdlib cimport *

cimport numpy
import numpy

from os import path

# logging import
import logging
logger=logging.getLogger()

# local imports
from pysph.base.particle_array cimport ParticleArray, LocalReal, Dummy
from pysph.base.nnps cimport NNPSManager, FixedDestNbrParticleLocator
from pysph.base.nnps cimport NbrParticleLocatorBase

from pysph.sph.sph_func cimport SPHFunction
from pysph.sph.funcs.basic_funcs cimport BonnetAndLokKernelGradientCorrectionTerms,\
    FirstOrderCorrectionMatrix, FirstOrderCorrectionTermAlpha, \
    FirstOrderCorrectionMatrixGradient, FirstOrderCorrectionVectorGradient

from pysph.base.carray cimport IntArray, DoubleArray

from pysph.solver.cl_utils import (HAS_CL, get_cl_include,
    get_pysph_root, cl_read)
if HAS_CL:
    import pyopencl as cl
    from pyopencl.array import vec

cdef int log_level = logger.level

###############################################################################
# `SPHCalc` class.
###############################################################################
cdef class SPHCalc:
    """ A general purpose summation object
    
    Members:
    --------
    sources -- a list of source particle arrays
    dest -- the destination particles array
    func -- the function to use between the source and destination
    nbr_loc -- a list of neighbor locator for each (source, dest)
    kernel -- the kernel to use
    nnps_manager -- the NNPSManager for the neighbor locator

    Notes:
    ------
    We assume that one particle array is being used in the simulation and
    hence, the source and destination, as well as the func's source and 
    destination are the same particle array.
    
    The particle array should define a flag `bflag` to indicate if a particle
    is a solid of fluid particle. The function can in turn distinguish 
    between these particles and decide whether to include the influence 
    or not.

    The base class and the subclass `SPHFluidSolid` assume that the 
    interaction is to be considered between both types of particles.
    Use the `SPHFluid` and `SPHSolid` subclasses to perform interactions 
    with fluids and solids respectively.
    
    """

    #Defined in the .pxd file
    #cdef public ParticleArray dest
    #cdef public list sources
    #cdef public list funcs
    #cdef public list nbr_locators
    #cdef public NNPSManager nnps_manager
    #cdef public KernelBase kernel
    #cdef public Particles particles
    #cdef public LongArray nbrs

    def __cinit__(self, particles, list sources, ParticleArray dest,
                  KernelBase kernel, list funcs,
                  list updates, integrates=False, dnum=0, nbr_info=True,
                  str id = "", bint kernel_gradient_correction=False,
                  kernel_correction=-1, int dim = 1, str snum=""):

        self.nbr_info = nbr_info
        self.particles = particles
        self.sources = sources
        self.nsrcs = len(sources)
        self.dest = dest
        self.nbr_locators = []

        self.nnps_manager = particles.nnps_manager

        self.funcs = funcs
        self.kernel = kernel

        self.nbrs = LongArray()

        self.integrates = integrates
        self.updates = updates
        self.nupdates = len(updates)

        self.kernel_correction = kernel_correction

        self.dnum = dnum
        self.id = id

        self.dim = dim
        self.snum = snum

        self.correction_manager = None

        self.tag = ""

        self.src_reads = []
        self.dst_reads = []
        self.initial_props = []
        self.dst_writes = {}

        self.context = object()
        self.queue = object()
        self.cl_kernel = object()
        self.cl_kernel_src_file = ''
        self.cl_kernel_function_name = ''

        self.check_internals()
        self.setup_internals()

    cpdef check_internals(self):
        """ Check for inconsistencies and set the neighbor locator. """

        # check if the data is sane.

        logger.info("SPHCalc:check_internals: calc %s"%(self.id))

        if (len(self.sources) == 0 or self.nnps_manager is None
            or self.dest is None or self.kernel is None or len(self.funcs)
            == 0):
            logger.warn('invalid input to setup_internals')
            logger.info('sources : %s'%(self.sources))
            logger.info('nnps_manager : %s'%(self.nnps_manager))
            logger.info('dest : %s'%(self.dest))
            logger.info('kernel : %s'%(self.kernel))
            logger.info('sph_funcs : %s'%(self.funcs)) 
            
            return

        # we need one sph_func for each source.

        if len(self.funcs) != len(self.sources):
            msg = 'One sph function is needed per source'
            raise ValueError, msg

        # ensure that all the funcs are of the same class and have same tag

        funcs = self.funcs
        for i in range(len(self.funcs)-1):
            if type(funcs[i]) != type(funcs[i+1]):
                msg = 'All sph_funcs should be of same type'
                raise ValueError, msg
            if funcs[i].tag != funcs[i+1].tag:
                msg = "All functions should have the same tag"
                raise ValueError, msg
        #check that the function src and dsts are the same as the calc's

        for i in range(len(self.funcs)):
            if funcs[i].source != self.sources[i]:
                msg = 'SPHFunction.source not same as'
                msg += ' SPHCalc.sources[%d]'%(i)
                raise ValueError, msg
            if funcs[i].num_outputs != len(self.updates):
                raise ValueError, ('Number of updates not same as num_outputs; '
                                   'required %d, got %d %s for func %s'%(
                                       funcs[i].num_outputs, len(self.updates),
                                       self.updates, funcs[i]))
            # not valid for SPHFunction
            #if funcs[i].dest != self.dest:
            #    msg = 'SPHFunction.dest not same as'
            #    msg += ' SPHCalc.dest'
            #    raise ValueError, msg

    cdef setup_internals(self):
        """ Set the update update arrays and neighbor locators """

        cdef FixedDestNbrParticleLocator loc
        cdef SPHFunction func
        cdef int nsrcs = self.nsrcs
        cdef ParticleArray src
        cdef int i

        self.nbr_locators[:] = []

        # set the calc's tag from the function tags. Check ensures all are same
        self.tag = self.funcs[0].tag
        self.cl_kernel_function_name = self.funcs[0].cl_kernel_function_name

        # set the neighbor locators
        for i in range(nsrcs):
            src = self.sources[i]
            func = self.funcs[i]

            # set the SPHFunction kernel
            func.kernel = self.kernel

            loc = self.nnps_manager.get_neighbor_particle_locator(
                src, self.dest, self.kernel.radius())
            func.nbr_locator = loc

            logger.info("""SPHCalc:setup_internals: calc %s using 
                        locator (src: %s) (dst: %s) %s """
                        %(self.id, src.name, self.dest.name, loc))
            
            self.nbr_locators.append(loc)

        func = self.funcs[0]

        self.src_reads = func.src_reads
        self.dst_reads = func.dst_reads

    cpdef sph(self, str output_array1=None, str output_array2=None, 
              str output_array3=None, bint exclude_self=False): 
        """
        """
        cdef DoubleArray output1 = self.dest.get_carray(output_array1)
        cdef DoubleArray output2 = self.dest.get_carray(output_array2)
        cdef DoubleArray output3 = self.dest.get_carray(output_array3)

        if output1 is not None:
            self.reset_output_array(output1)
        if output2 is not None:
            self.reset_output_array(output2)
        if output3 is not None:
            self.reset_output_array(output3)

        self.sph_array(output1, output2, output3, exclude_self)

        # call an update on the particles if the destination pa is dirty

        if self.dest.is_dirty:
            self.particles.update()

    cpdef sph_array(self, DoubleArray output1, DoubleArray output2, DoubleArray
                     output3, bint exclude_self=False):
        """
        Similar to the sph1 function, except that this can handle
        SPHFunction that compute 3 output fields.

        **Parameters**
        
         - output1 - the array to store the first output component.
         - output2 - the array to store the second output component.
         - output3 - the array to store the third output component.
         - exclude_self - indicates if each particle itself should be left out
           of the computations.

        """

        cdef SPHFunction func

        if self.kernel_correction != -1 and self.nbr_info:
            self.correction_manager.set_correction_terms(self)
        
        for func in self.funcs:
            func.nbr_locator = self.nnps_manager.get_neighbor_particle_locator(
                func.source, self.dest, self.kernel.radius())

            func.eval(self.kernel, output1, output2, output3)

    cdef reset_output_array(self, DoubleArray output):

        cdef int i
        for i in range(output.length):
            output.data[i] = 0.0

#############################################################################

class CLCalc(SPHCalc):
    """ OpenCL aware SPHCalc """

    def setup_cl_kernel_file(self):
        func = self.funcs[0]
        
        src = get_pysph_root()
        src = path.join(src, 'sph/funcs/' + func.cl_kernel_src_file)

        if not path.isfile(src):
            fname = self.func.cl_kernel_src_file
            logger.debug("OpenCL kernel file does not exist: %s"%fname)
            
        self.cl_kernel_src_file = src

    def setup_cl(self, context):
        """ Setup the CL related stuff

        Parameters:
        -----------

        context -- the OpenCL context to use

        The Calc creates an OpenCL CommandQueue using, by default, the
        first available device within the context.

        The ParticleArrays are allocated on the device by calling
        their respective setup_cl functions.

        I guess we would need a clean way to deallocate the device
        arrays once we are through with one step and move on to the
        next.

        """
        self.setup_cl_kernel_file()
        
        self.context = context
        self.devices = context.devices

        # create a command queue with the first device on the context 
        self.queue = cl.CommandQueue(context, self.devices[0])

        # set up the device buffers for the srcs and dest

        self.dest.setup_cl(self.context, self.queue)

        for src in self.sources:
            src.setup_cl(self.context, self.queue)

        self.setup_program()

    def _create_program(self, template):
        """Given a program source template, flesh out the code and
        return it.

        An OpenCL kernel template requires the following pieces of
        code to make it a valid OpenCL kerel file:

        kernel_args -- the arguments for the kernel injected by the
                       function.

        workgroup_code -- code injected by the function to get the
                          global id from the kernel launch parameters.

        neighbor_loop_code -- code injected by the neighbor locator to
                              determine the next neighbor for a given
                              particle                       

        """
        k_args = []

        for func in self.funcs:
            func.set_cl_kernel_args()

        func = self.funcs[0]
        k_args.extend(func.cl_args_name)

        # Build the kernel args string.
        kernel_args = ',\n    '.join(k_args)

        # Get the kernel workgroup code
        workgroup_code = func.get_cl_workgroup_code()

        # Construct the neighbor loop code.
        neighbor_loop_code = "for (int src_id=0; src_id<nbrs; ++src_id)"

        return template%(locals())

    def setup_program(self):
        """ Setup the OpenCL function used by this Calc
        
        The calc computes the interaction on a single destination from
        a list of sources, using the same function.

        A call to this function sets up the OpenCL kernel which
        encapsulates the SPHFunction function.

        The OpenCL source file template is read and suitable code is
        injected to make it work.

        An example template file is 'sph/funcs/density_funcs.cl'

        """

        prog_src_tmp = cl_read(self.cl_kernel_src_file,
                               precision=self.particles.get_cl_precision(),
                               function_name=self.cl_kernel_function_name)

        prog_src = self._create_program(prog_src_tmp)

        self.cl_kernel_src = prog_src

        build_options = get_cl_include()

        self.prog = cl.Program(self.context, prog_src).build(
            build_options)

        # set the OpenCL kernel for each of the SPHFunctions
        for func in self.funcs:
            func.setup_cl(self.prog, self.context)
        
    def sph(self):
        """ Evaluate the contribution from the sources on the
        destinations using OpenCL.

        Each of the ParticleArray's properties has an equivalent device
        representation. The devie buffers have the suffix `cl_` so that
        a numpy array `rho` on the host has the buffer `cl_rho` on the device.

        The device buffers are created upon a call to CLCalc's setup_cl
        function. The CommandQueue is created using the first device
        in the context as default. This could be changed in later
        revisions.
        
        Each of the device buffers can be obtained like so:

        pa.get_cl_buffer(prop)

        where prop may not be suffixed with 'cl_'
        
        The OpenCL kernel functions have the signature:

        __kernel void function(__global int* kernel_type, __global int* dim,
                               __global int* nbrs,
                               __global float* d_x, __global float* d_y,
                               __global_float* d_z, __global float* d_h,
                               __global int* d_tag,
                               __global float* s_x, __global float* s_y,
                               ...,
                               __global float* tmpx, ...)

        Thus, the first three arguments are the sph kernel type,
        dimension and a list of neighbors for the destination particle.

        The following properties are the destination particle array
        properties that are required. This is defined in each function
        as the attribute dst_reads

        The last arguments are the source particle array properties
        that are required. This i defined in each function as the
        attribute src_reads.

        The final arguments are the output arrays to which we want to
        append the result. The number of the output arguments can vary
        based on the function.
    
        """
        
        # set the tmpx, tmpy and tmpz arrays for dest to 0

        self.cl_reset_output_arrays()

        for func in self.funcs:
            func.cl_eval(self.queue, self.context)

    def cl_reset_output_arrays(self):
        """ Reset the dst tmpx, tmpy and tmpz arrays to 0

        Since multiple functions contribute to the same LHS value, the
        OpenCL kernel code increments the result to tmpx, tmpy and tmpz.
        To avoid unplesant behavior, we set these variables to 0 before
        any function is called.
        
        """

        if not self.dest.cl_setup_done:
            raise RuntimeWarning, "CL not setup on destination array!"

        dest = self.dest

        cl_tmpx = dest.get_cl_buffer('_tmpx')
        cl_tmpy = dest.get_cl_buffer('_tmpy')
        cl_tmpz = dest.get_cl_buffer('_tmpz')

        npd = self.dest.get_number_of_particles()

        self.prog.set_tmp_to_zero(self.queue, (npd, 1, 1), (1, 1, 1),
                                  cl_tmpx, cl_tmpy, cl_tmpz).wait()

#############################################################################
