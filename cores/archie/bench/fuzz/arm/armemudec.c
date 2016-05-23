    switch ((int)BITS(24,27)) {
      case 0x0: {
          int i = BITS(20,23);
          if((i<4) && (BITS(4,7) == 9)) {
            static ARMEmuFunc funcs0[4]={
              EMFUNCDECL26(Mul), EMFUNCDECL26(Muls), EMFUNCDECL26(Mla), EMFUNCDECL26(Mlas)
            };
            f=funcs0[i];
          } else {            
            static ARMEmuFunc funcs0[16]={
              EMFUNCDECL26(AndReg), EMFUNCDECL26(AndsReg), EMFUNCDECL26(EorReg), EMFUNCDECL26(EorsReg),
              EMFUNCDECL26(SubReg), EMFUNCDECL26(SubsReg), EMFUNCDECL26(RsbReg), EMFUNCDECL26(RsbsReg),
              EMFUNCDECL26(AddReg), EMFUNCDECL26(AddsReg), EMFUNCDECL26(AdcReg), EMFUNCDECL26(AdcsReg),
              EMFUNCDECL26(SbcReg), EMFUNCDECL26(SbcsReg), EMFUNCDECL26(RscReg), EMFUNCDECL26(RscsReg)
            };
            f=funcs0[i];
          }
        };
      break;

      case 0x1: {
        static ARMEmuFunc funcs1[2][16]={
          { EMFUNCDECL26(TstRegMrs1SwpNorm),EMFUNCDECL26(TstpRegNorm),EMFUNCDECL26(Noop),EMFUNCDECL26(TeqpRegNorm),
            EMFUNCDECL26(CmpRegMrs2SwpNorm),EMFUNCDECL26(CmppRegNorm),EMFUNCDECL26(Noop),EMFUNCDECL26(CmnpRegNorm),
            EMFUNCDECL26(OrrRegNorm),EMFUNCDECL26(OrrsRegNorm),EMFUNCDECL26(MovRegNorm),EMFUNCDECL26(MovsRegNorm),
            EMFUNCDECL26(BicRegNorm),EMFUNCDECL26(BicsRegNorm),EMFUNCDECL26(MvnRegNorm),EMFUNCDECL26(MvnsRegNorm)
          }, {
            EMFUNCDECL26(TstRegMrs1SwpPC), EMFUNCDECL26(TstpRegPC), EMFUNCDECL26(Noop), EMFUNCDECL26(TeqpRegPC),
            EMFUNCDECL26(CmpRegMrs2SwpPC), EMFUNCDECL26(CmppRegPC), EMFUNCDECL26(Noop), EMFUNCDECL26(CmnpRegPC),
            EMFUNCDECL26(OrrRegPC), EMFUNCDECL26(OrrsRegPC), EMFUNCDECL26(MovRegPC), EMFUNCDECL26(MovsRegPC),
            EMFUNCDECL26(BicRegPC), EMFUNCDECL26(BicsRegPC), EMFUNCDECL26(MvnRegPC), EMFUNCDECL26(MvnsRegPC)
          }
        };
        f=funcs1[(DESTReg==15)][((int)BITS(20,23))];
      };
      break;

      case 0x2: {
        static ARMEmuFunc funcsdata[16] = {
           EMFUNCDECL26(AndImm), EMFUNCDECL26(AndsImm),     EMFUNCDECL26(EorImm), EMFUNCDECL26(EorsImm),
           EMFUNCDECL26(SubImm), EMFUNCDECL26(SubsImmNorm), EMFUNCDECL26(RsbImm), EMFUNCDECL26(RsbsImm),
           EMFUNCDECL26(AddImm), EMFUNCDECL26(AddsImm),     EMFUNCDECL26(AdcImm), EMFUNCDECL26(AdcsImm),
           EMFUNCDECL26(SbcImm), EMFUNCDECL26(SbcsImm),     EMFUNCDECL26(RscImm), EMFUNCDECL26(RscsImm)
        };

        f = funcsdata[(int)BITS(20,23)];
      };
      break;

      case 0x3: {
        static ARMEmuFunc funcs3[16]={
          EMFUNCDECL26(Noop), EMFUNCDECL26(TstpImm), EMFUNCDECL26(Noop), EMFUNCDECL26(TeqpImm),
          EMFUNCDECL26(Noop), EMFUNCDECL26(CmppImm), EMFUNCDECL26(Noop), EMFUNCDECL26(CmnpImm),
          EMFUNCDECL26(OrrImm), EMFUNCDECL26(OrrsImm), EMFUNCDECL26(MovImm), EMFUNCDECL26(MovsImm),
          EMFUNCDECL26(BicImm), EMFUNCDECL26(BicsImm), EMFUNCDECL26(MvnImm), EMFUNCDECL26(MvnsImm)
        };
        f=funcs3[(int)BITS(20,23)];
      };
      break;

      case 0x4: {
        static ARMEmuFunc funcs4[16]={
          EMFUNCDECL26(StoreNoWritePostDecImm), EMFUNCDECL26(LoadNoWritePostDecImm), EMFUNCDECL26(StoreWritePostDecImm), EMFUNCDECL26(LoadWritePostDecImm),
          EMFUNCDECL26(StoreBNoWritePostDecImm), EMFUNCDECL26(LoadBNoWritePostDecImm), EMFUNCDECL26(StoreBWritePostDecImm), EMFUNCDECL26(LoadBWritePostDecImm),
          EMFUNCDECL26(StoreNoWritePostIncImm), EMFUNCDECL26(LoadNoWritePostIncImm), EMFUNCDECL26(StoreWritePostIncImm), EMFUNCDECL26(LoadWritePostIncImm),
          EMFUNCDECL26(StoreBNoWritePostIncImm), EMFUNCDECL26(LoadBNoWritePostIncImm), EMFUNCDECL26(StoreBWritePostIncImm), EMFUNCDECL26(LoadBWritePostIncImm)
        };
        f=funcs4[(int)BITS(20,23)];
      };
      break;

      case 0x5: {
        static ARMEmuFunc funcs5[16]={
          EMFUNCDECL26(StoreNoWritePreDecImm), EMFUNCDECL26(LoadNoWritePreDecImm), EMFUNCDECL26(StoreWritePreDecImm), EMFUNCDECL26(LoadWritePreDecImm),
          EMFUNCDECL26(StoreBNoWritePreDecImm), EMFUNCDECL26(LoadBNoWritePreDecImm), EMFUNCDECL26(StoreBWritePreDecImm), EMFUNCDECL26(LoadBWritePreDecImm),
          EMFUNCDECL26(StoreNoWritePreIncImm), EMFUNCDECL26(LoadNoWritePreIncImm), EMFUNCDECL26(StoreWritePreIncImm), EMFUNCDECL26(LoadWritePreIncImm),
          EMFUNCDECL26(StoreBNoWritePreIncImm), EMFUNCDECL26(LoadBNoWritePreIncImm), EMFUNCDECL26(StoreBWritePreIncImm), EMFUNCDECL26(LoadBWritePreIncImm)
        };
        f=funcs5[(int)BITS(20,23)];
      };
      break;

      case 0x6:
        if (BIT(4)) {
          f=EMFUNCDECL26(Undef);
        } else {
          static ARMEmuFunc funcs6[16]={
            EMFUNCDECL26(StoreNoWritePostDecReg), EMFUNCDECL26(LoadNoWritePostDecReg), EMFUNCDECL26(StoreWritePostDecReg), EMFUNCDECL26(LoadWritePostDecReg),
            EMFUNCDECL26(StoreBNoWritePostDecReg), EMFUNCDECL26(LoadBNoWritePostDecReg), EMFUNCDECL26(StoreBWritePostDecReg), EMFUNCDECL26(LoadBWritePostDecReg),
            EMFUNCDECL26(StoreNoWritePostIncReg), EMFUNCDECL26(LoadNoWritePostIncReg), EMFUNCDECL26(StoreWritePostIncReg), EMFUNCDECL26(LoadWritePostIncReg),
            EMFUNCDECL26(StoreBNoWritePostIncReg), EMFUNCDECL26(LoadBNoWritePostIncReg), EMFUNCDECL26(StoreBWritePostIncReg), EMFUNCDECL26(LoadBWritePostIncReg)
          };
          f=funcs6[(int)BITS(20,23)];
        };
      break;

      case 0x7:
        if (BIT(4)) {
          f=EMFUNCDECL26(Undef);
        } else {
          static ARMEmuFunc funcs7[16]={
            EMFUNCDECL26(StoreNoWritePreDecReg), EMFUNCDECL26(LoadNoWritePreDecReg), EMFUNCDECL26(StoreWritePreDecReg), EMFUNCDECL26(LoadWritePreDecReg),
            EMFUNCDECL26(StoreBNoWritePreDecReg), EMFUNCDECL26(LoadBNoWritePreDecReg), EMFUNCDECL26(StoreBWritePreDecReg), EMFUNCDECL26(LoadBWritePreDecReg),
            EMFUNCDECL26(StoreNoWritePreIncReg), EMFUNCDECL26(LoadNoWritePreIncReg), EMFUNCDECL26(StoreWritePreIncReg), EMFUNCDECL26(LoadWritePreIncReg),
            EMFUNCDECL26(StoreBNoWritePreIncReg), EMFUNCDECL26(LoadBNoWritePreIncReg), EMFUNCDECL26(StoreBWritePreIncReg), EMFUNCDECL26(LoadBWritePreIncReg)
          };
          f=funcs7[(int)BITS(20,23)];
        };
      break;

      case 0x8: {
        static ARMEmuFunc funcs8[16]={
          EMFUNCDECL26(MultiStorePostDec), EMFUNCDECL26(MultiLoadPostDec), EMFUNCDECL26(MultiStoreWritePostDec), EMFUNCDECL26(MultiLoadWritePostDec),
          EMFUNCDECL26(MultiStoreFlagsPostDec), EMFUNCDECL26(MultiLoadFlagsPostDec), EMFUNCDECL26(MultiStoreWriteFlagsPostDec), EMFUNCDECL26(MultiLoadWriteFlagsPostDec),
          EMFUNCDECL26(MultiStorePostInc), EMFUNCDECL26(MultiLoadPostInc), EMFUNCDECL26(MultiStoreWritePostInc), EMFUNCDECL26(MultiLoadWritePostInc),
          EMFUNCDECL26(MultiStoreFlagsPostInc), EMFUNCDECL26(MultiLoadFlagsPostInc), EMFUNCDECL26(MultiStoreWriteFlagsPostInc), EMFUNCDECL26(MultiLoadWriteFlagsPostInc)
        };
        f=funcs8[(int)BITS(20,23)];
      };
      break;

      case 0x9: {
        static ARMEmuFunc funcs9[16]={
          EMFUNCDECL26(MultiStorePreDec), EMFUNCDECL26(MultiLoadPreDec), EMFUNCDECL26(MultiStoreWritePreDec), EMFUNCDECL26(MultiLoadWritePreDec),
          EMFUNCDECL26(MultiStoreFlagsPreDec), EMFUNCDECL26(MultiLoadFlagsPreDec), EMFUNCDECL26(MultiStoreWriteFlagsPreDec), EMFUNCDECL26(MultiLoadWriteFlagsPreDec),
          EMFUNCDECL26(MultiStorePreInc), EMFUNCDECL26(MultiLoadPreInc), EMFUNCDECL26(MultiStoreWritePreInc), EMFUNCDECL26(MultiLoadWritePreInc),
          EMFUNCDECL26(MultiStoreFlagsPreInc), EMFUNCDECL26(MultiLoadFlagsPreInc), EMFUNCDECL26(MultiStoreWriteFlagsPreInc), EMFUNCDECL26(MultiLoadWriteFlagsPreInc)
        };

        f=funcs9[(int)BITS(20,23)];

      };
      break;

      case 0xa:
      f = EMFUNCDECL26(Branch);
      break;

      case 0xb:
      f = EMFUNCDECL26(BranchLink);
      break;

      case 0xc:
      switch ((int)BITS(20,23)) {
        case 0x0:
        case 0x4:
          f=EMFUNCDECL26(CoStoreNoWritePostDec);
          break;

        case 0x1:
        case 0x5:
          f=EMFUNCDECL26(CoLoadNoWritePostDec);
          break;


        case 0x2:
        case 0x6:
          f=EMFUNCDECL26(CoStoreWritePostDec);
          break;

        case 0x3:
        case 0x7:
          f=EMFUNCDECL26(CoLoadWritePostDec);
          break;

        case 0x8:
        case 0xc:
          f=EMFUNCDECL26(CoStoreNoWritePostInc);
          break;

        case 0x9:
        case 0xd:
          f=EMFUNCDECL26(CoLoadNoWritePostInc);
          break;

        case 0xa:
        case 0xe:
          f=EMFUNCDECL26(CoStoreWritePostInc);
          break;

	/*case 0xb:
	  case 0xf:*/
        default:
          f=EMFUNCDECL26(CoLoadWritePostInc);
          break;
      };
      break;

      case 0xd:
      switch ((int)BITS(20,23)) {
        case 0x0:
        case 0x4:
          f=EMFUNCDECL26(CoStoreNoWritePreDec);
          break;

        case 0x1:
        case 0x5:
          f=EMFUNCDECL26(CoLoadNoWritePreDec);
          break;


        case 0x2:
        case 0x6:
          f=EMFUNCDECL26(CoStoreWritePreDec);
          break;

        case 0x3:
        case 0x7:
          f=EMFUNCDECL26(CoLoadWritePreDec);
          break;

        case 0x8:
        case 0xc:
          f=EMFUNCDECL26(CoStoreNoWritePreInc);
          break;

        case 0x9:
        case 0xd:
          f=EMFUNCDECL26(CoLoadNoWritePreInc);
          break;

        case 0xa:
        case 0xe:
          f=EMFUNCDECL26(CoStoreWritePreInc);
          break;

	/*case 0xb:
	  case 0xf:*/
        default:
          f=EMFUNCDECL26(CoLoadWritePreInc);
          break;

      };
      break;

      case 0xe:
      {
        f = (instr & (UINT32_C(1) << 20)) ? EMFUNCDECL26(CoMRCDataOp) : EMFUNCDECL26(CoMCRDataOp);
      };
      break;

      /* case 0xf:*/
      default:
        f=EMFUNCDECL26(SWI);
        break;
    };
