import { Reflector } from '@nestjs/core';
import { RoleCode } from '../schemas/role.schema';

export const Roles = Reflector.createDecorator<RoleCode[]>();
