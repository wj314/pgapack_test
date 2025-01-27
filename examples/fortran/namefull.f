c  PGAPack test program.
c
c  The objective is to evolve a string of characters to match a string
c  supplied by the user.  We will stop evolving when either we run out
c  of iterations (500), or when the best string has the same evaluation
c  value for 100 generations.
c
c  One problem with this implementation is that ' ' is not in
c  PGA_DATATYPE_CHAR if we limit it using PGA_CINIT_MIXED, PGA_CINIT_LOWER,
c  or PGA_CINIT_UPPER.  To fix this, we must define our own interval, and
c  thus, our own mutation, initialization operators.
c
c  A user function is also used to check the "done" condition; we are 
c  done if we've done more than 1000 iterations, or the evolved string
c  is correct.
c
c  Created 28 Sep 95, Brian P. Walenz.  Thanks to Dan Ashlock for the idea.
c
      include 'pgapackf.h'

      

      integer          N_Mutation
      integer          N_Duplicate
      integer          N_StopCond
      double precision EvalName
      
      external   N_Mutation
      external   N_Duplicate
      external   N_StopCond
      external   EvalName
      external   N_Crossover
      external   N_InitString
      external   N_PrintString
      external   N_EndOfGeneration

c     I'm not claiming to be a FORTRAN hacker, so if you want to use
c     a string other than what is supplied, you must change the lengths 
c     to correspond to the length of the new string.
c     Also, this is common, sunce we need it in EvalName.
      character*70     Name
      common /global/  Name

      integer(8)      ctx
      integer         ierror


      call MPI_Init(ierror)

      Name = 'David M. Levine, Philip L. Hallstrom, David M. Noelle,'
     &        // ' Brian P. Walenz'

      ctx = PGACreate(PGA_DATATYPE_CHARACTER, 70, PGA_MAXIMIZE)
    
      call PGASetRandomSeed(ctx, 42)
    
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_INITSTRING,
     &     N_InitString)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_MUTATION,
     &     N_Mutation)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_CROSSOVER,
     &     N_Crossover)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_DUPLICATE,
     &     N_Duplicate)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_STOPCOND,
     &     N_StopCond)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_ENDOFGEN,
     &     N_EndOfGeneration)
      call PGASetUserFunction(ctx, PGA_USERFUNCTION_PRINTSTRING,
     &     N_PrintString)

c     We don't want to report anything.
      call PGASetPrintFrequencyValue(ctx, 10000)

      call PGASetPopSize(ctx, 100)
      call PGASetNumReplaceValue(ctx, 90)
      call PGASetPopReplaceType(ctx, PGA_POPREPL_BEST)

      call PGASetNoDuplicatesFlag(ctx, PGA_TRUE)

      call PGASetMaxGAIterValue(ctx, 100)
    
      call PGASetUp(ctx)
      call PGARun(ctx, EvalName)
      call PGADestroy(ctx)

      call MPI_Finalize(ierror)

      stop
      end


c     Function to randomly initialize a PGA_DATATYPE_CHARACTER string 
c     using all printable ASCII characters for the range.
c
      subroutine N_InitString(ctx, p, pop) 
      include   'pgapackf.h'
      integer(8)      ctx
      integer         p, pop, i
    
      do i=PGAGetStringLength(ctx), 1, -1
         call PGASetCharacterAllele(ctx, p, pop, i,
     &        char(PGARandomInterval(ctx, 32, 126)))
      enddo

      return
      end


c     Function to crossover two name strings.  Quite an interesting
c     crossover, too.  Works like a normal uniform crossover, except
c     that, if one of the strings matches the correct value, we set
c     BOTH children to the correct value 50% of the time.
c
      subroutine N_Crossover(ctx, p1, p2, pop1, c1, c2, pop2)
      include          'pgapackf.h'
      character         Name(70)
      common /global/   Name
      integer(8)        ctx
      integer           p1, p2, pop1, c1, c2, pop2
      integer           i, length
      character         a, b

      length = PGAGetStringLength(ctx)

      do i=1, length
         a = PGAGetCharacterAllele(ctx, p1, pop1, i)
         b = PGAGetCharacterAllele(ctx, p2, pop1, i)
         if ((a .eq. Name(i)) .or. (b .eq. Name(i))) then
            a = Name(i)
            b = Name(i)
         endif

         if (PGARandomFlip(ctx, 0.5d0) .eq. PGA_TRUE) then
            call PGASetCharacterAllele(ctx, c1, pop2, i, a)
            call PGASetCharacterAllele(ctx, c2, pop2, i, b)
         else
            call PGASetCharacterAllele(ctx, c1, pop2, i, b)
            call PGASetCharacterAllele(ctx, c2, pop2, i, a)
         endif
      enddo
   
      return
      end


c     Function to compare two strings.  Strings are "equalivalent"
c     if they match Name at the same alleles (and, thus, disagree at the
c     same alleles).  We don't care what the disagreement is, just that
c     it is there.
c
      integer function N_Duplicate(ctx, p1, pop1, p2, pop2)
      include          'pgapackf.h'
      character         Name(70)
      common /global/   Name
      integer(8)        ctx
      integer           p1, pop1, p2, pop2
      integer           i, match
      character         a, b, c

      match = PGA_TRUE

      do i=PGAGetStringLength(ctx), 1, -1
         a = PGAGetCharacterAllele(ctx, p1, pop1, i)
         b = PGAGetCharacterAllele(ctx, p2, pop2, i)
         c = Name(i)
         if (((a .eq. c) .and. (b .ne. c)) .or.
     &        ((a .ne. c) .and. (b .eq. c))) then
            match = PGA_FALSE
            goto 10
         endif
      enddo

 10   N_Duplicate = match
      
      return
      end
      


c     Function to muatate a PGA_DATATYPE_CHARACTER string.  This is 
c     done by simply picking allele locations and replacing whatever
c     was there with a new value.  Again, legal values are all
c     printable ASCII characters.
c
      integer function N_Mutation(ctx, p, pop, mr)
      include          'pgapackf.h'
      character         Name(70)
      common /global/   Name
      integer(8)        ctx
      integer           p, pop, i, count
      double precision  mr

      count = 0

      do i=PGAGetStringLength(ctx), 1, -1
         if (PGAGetCharacterAllele(ctx, p, pop, i) .ne. Name(i)) then
            if (PGARandomFlip(ctx, mr) .eq. PGA_TRUE) then
               call PGASetCharacterAllele(ctx, p, pop, i,
     &              char(PGARandomInterval(ctx, 32, 126)))
               count = count + 1
            endif
         endif
      enddo
           
      N_Mutation = count
      return
      end


c     Function to print a string.  Since fortran does NOT support
c     C file handles, we just print normally.  If we we're in C,
c     we would print to the file "file".
c     
      subroutine N_PrintString(ctx, file, p, pop)
      include          'pgapackf.h'
      integer(8)        ctx
      integer           file, p, pop
      character         string(70)

      do i=PGAGetStringLength(ctx), 1, -1
         string(i) = PGAGetCharacterAllele(ctx, p, pop, i)
      enddo

      print *, ':', string, ':'

      return
      end



c     Function to check "doneness" of the GA.  We check the iteration
c     count (by calling the system PGADone), then check if we have found
c     the string yet.
c
      integer function N_StopCond(ctx) 
      include          'pgapackf.h'
      integer(8)        ctx
      integer           done, best


      done = PGACheckStoppingConditions(ctx)

      best = PGAGetBestIndex(ctx, PGA_OLDPOP)
      if ((done .eq. PGA_FALSE) .and. 
     &     (PGAGetEvaluation(ctx, best, PGA_OLDPOP) .eq.
     &      PGAGetStringLength(ctx))) then
         done = PGA_TRUE
      endif

      N_StopCond = done
      return
      end

c     After each generation, this routine is called.  What is done here,
c     is to print the best string in our own format, then check if the
c     best string is close to the correct value.  If it is, duplicate
c     checking is tunred off.  This is critical, as the mutation operator
c     will not degrade a string, so when the strings get near the correct
c     solution, they all become duplicates, but none can be changed!
c
c     Other applications have done such things as send the best string 
c     to another process to be visualized.  For here, we just call our
c     print string function to print the best string.
c
      subroutine N_EndOfGeneration(ctx)
      include          'pgapackf.h'
      integer(8)        ctx
      integer           best

      best = PGAGetBestIndex(ctx, PGA_NEWPOP)

      call N_PrintString(ctx, 0, best, PGA_NEWPOP)

      if (PGAGetEvaluation(ctx, best, PGA_NEWPOP) .ge.
     &     PGAGetStringLength(ctx)-10) then
         call PGASetNoDuplicatesFlag(ctx, PGA_FALSE)
      endif
      
      return
      end
      
    
c     Evaluate the string.  A highly fit string will have many of
c     the characters matching Name.
c
      double precision function EvalName(ctx, p, pop)
      include          'pgapackf.h'
      integer(8)        ctx
      integer           p, pop, i, count
      character         Name(70)
      common /global/   Name
    
      count = 0
      do i=PGAGetStringLength(ctx), 1, -1
         if (PGAGetCharacterAllele(ctx, p, pop, i) .eq. Name(i)) then
            count = count + 1
         endif
      enddo

      EvalName = dble(count)
      return
      end
