import { Reflector } from '@nestjs/core';
import { Permission } from '../../core/schemas/apikey.schema';

export const Permissions = Reflector.createDecorator<Permission[]>();
