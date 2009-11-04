cimport numpy as np
from pysph.base.particle_tags cimport ParticleTag
from pysph.base.carray cimport LongArray

cdef class ParticleArray:
    """
    Maintains various properties for particles.
    """
    # dictionary to hold the properties held per particle.
    cdef public dict properties
    cdef public list property_arrays

    # default value associated with each property
    cdef public dict default_values

    # dictionary to hold temporary arrays - we can do away with this.
    cdef public dict temporary_arrays

    # the particle manager of which this is part of.
    cdef public object particle_manager

    # name associated with this particle array
    cdef public str name

    # indicates if coordinates of particles has changed.
    cdef public bint is_dirty

    cdef object _create_c_array_from_npy_array(self, np.ndarray arr)
    cdef _check_property(self, str)

    cpdef set_dirty(self, bint val)

    cpdef get_carray(self, str prop)

    cpdef int get_number_of_particles(self)
    cpdef remove_particles(self, LongArray index_list)
    cpdef remove_tagged_particles(self, long tag)

    # function to add any property
    cpdef add_property(self, dict prop_info)
    
    # increase the number of particles by num_particles
    cpdef extend(self, int num_particles)

    # function to remove particles with particular value of a flag property.
    #cpdef remove_flagged_particles(self, str flag_name, int flag_value)
